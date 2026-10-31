import json
import os
import urllib.parse
from io import BytesIO

import boto3
from PIL import Image, ImageOps

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

WEBSITE_BUCKET = os.environ["WEBSITE_BUCKET"]   # set in Step 13
TABLE = dynamodb.Table(os.environ["TABLE_NAME"])  # PhotoCatalog

WEB_WIDTH = 1600    # width of the version shown on the site
THUMB_WIDTH = 400   # width of the gallery thumbnail


def resize(image, width):
    """Shrink an image to the given width, keeping its proportions."""
    if image.width <= width:
        return image.copy()
    height = round(image.height * width / image.width)
    return image.resize((width, height), Image.LANCZOS)


def to_jpeg_bytes(image):
    """Turn a Pillow image into JPEG bytes ready for upload."""
    buffer = BytesIO()
    image.convert("RGB").save(buffer, "JPEG", quality=88)
    buffer.seek(0)
    return buffer


def process_photo(bucket, key):
    """Resize one uploaded photo, publish both sizes, catalog it."""
    filename = key.split("/")[-1]
    stem = filename.rsplit(".", 1)[0]          # file name without .jpg

    # Download the photo from the originals bucket
    response = s3.get_object(Bucket=bucket, Key=key)
    image = Image.open(BytesIO(response["Body"].read()))

    # Read EXIF BEFORE rotating, so no metadata is lost
    exif = image.getexif()
    camera = str(exif.get(272, "")).strip()            # 272 = camera model
    date_taken = str(exif.get(306, ""))[:10]           # 306 = date, keep YYYY-MM-DD

    # Fix sideways photos using the orientation flag cameras embed
    image = ImageOps.exif_transpose(image)

    # Publish the two web sizes to the website bucket
    web_key = f"images/{stem}.jpg"
    thumb_key = f"thumbs/{stem}.jpg"
    s3.put_object(Bucket=WEBSITE_BUCKET, Key=web_key,
                  Body=to_jpeg_bytes(resize(image, WEB_WIDTH)),
                  ContentType="image/jpeg")
    s3.put_object(Bucket=WEBSITE_BUCKET, Key=thumb_key,
                  Body=to_jpeg_bytes(resize(image, THUMB_WIDTH)),
                  ContentType="image/jpeg")

    # File the catalog record. photoId = file name, so re-uploading
    # the same photo updates its record instead of duplicating it.
    TABLE.put_item(Item={
        "photoId": stem,
        "title": stem.replace("-", " ").replace("_", " ").title(),
        "imageKey": web_key,
        "thumbKey": thumb_key,
        "camera": camera,
        "dateTaken": date_taken,
    })
    print(f"Processed {key}")


def rebuild_manifest():
    """Rewrite photos.json — the index file the web page reads."""
    items = TABLE.scan().get("Items", [])   # fine at this scale
    manifest = [{
        "title": i.get("title", ""),
        "image": i.get("imageKey", ""),
        "thumb": i.get("thumbKey", ""),
        "camera": i.get("camera", ""),
        "date": i.get("dateTaken", ""),
    } for i in sorted(items, key=lambda x: x.get("dateTaken", ""), reverse=True)]
    s3.put_object(Bucket=WEBSITE_BUCKET, Key="photos.json",
                  Body=json.dumps(manifest).encode("utf-8"),
                  ContentType="application/json", CacheControl="no-cache")


def lambda_handler(event, context):
    """Entry point — S3 calls this every time a file lands in originals."""
    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        if not key.lower().endswith((".jpg", ".jpeg", ".png")):
            print(f"Skipping non-image file: {key}")
            continue
        process_photo(bucket, key)
    rebuild_manifest()
    return {"statusCode": 200, "body": "OK"}
