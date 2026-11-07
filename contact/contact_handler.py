import json
import os

import boto3

RECIPIENT = os.environ["RECIPIENT_EMAIL"]
ses = boto3.client("ses")

def lambda_handler(event, context):
    body = json.loads(event["body"])

    name = body.get("name", "")
    email = body.get("email", "")
    message_text = body.get("message", "")

    if not name or not email or not message_text:
        return{
            "statusCode": 400,
            "body": json.dumps({"message": "Please fill out all fields."}),
        }
    message = f"Name: {name}\nEmail: {email}\nMessage: {message_text}"
    
    try:
        ses.send_email(
            Source=RECIPIENT,
            Destination={"ToAddresses": [RECIPIENT]},
            ReplyToAddresses=[email],
            Message={
                "Subject": {"Data": f"Stem and Stars Inquiry - {name}"},
                "Body": {"Text": {"Data": message}},
            },
        )
    except Exception as e:
        print(e)
        return {
            "statusCode": 500,
            "body": json.dumps({"message": "Something went wrong. Please try again."}),
        }
    return {
        "statusCode": 200,
        "body": json.dumps({"message": "Message sent."}),
    }    
    
