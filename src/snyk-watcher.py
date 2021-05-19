import json
import os
import traceback

import requests

# Snyk's import project API structure is as follows:
# https://snyk.io/api/v1/org/<SNYK_ORGANIZATION_ID>/integrations/<GITLAB_INTEGRATION_ID>/import/
# Set the constants below with your Organization and Integration IDs which can be found in the Snyk UI or via API calls
SNYK_ORGANIZATION_ID = "REPLACE_ME"
GITLAB_INTEGRATION_ID = "REPLACE_ME"

# This is your Snyk API Token:
snyk_token = os.getenv("SNYK_TOKEN")

# hook_validation_token is used to ensure the System Hook is the one calling with the secret
hook_validation_token = os.getenv("HOOK_VALIDATION_TOKEN")


def call_snyk(gl_project_name, gl_project_id):
    data = {"target": {"id": gl_project_id, "branch": "master"}, "files": []}
    headers = {
        'Authorization': f'token: {snyk_token}',
        'Content-Type': 'application/json'
    }

    url = f"https://snyk.io/api/v1/org/{SNYK_ORGANIZATION_ID}/integrations/{GITLAB_INTEGRATION_ID}/import/"
    response = requests.post(url, json=data, headers=headers)

    if response.status_code != 201:
        raise Exception(f"Failed to import repository: {gl_project_name}, {gl_project_id}")

    return response


def lambda_handler(event, context=None):
    if hook_validation_token is None:
        print("*** No HOOK_VALIDATION_TOKEN. ***")
        raise ValueError(f"Missing HOOK_VALIDATION_TOKEN env variable")

    try:
        if hook_validation_token is None:
            return {
                "statusCode": 403,
                "body": "Security token did not match or was not provided",
            }

        hook_data = event.get("body")
        if hook_data is None:
            print("Event with empty body received. Ignoring.")
            return {"statusCode": 400, "body": "No body content found in request"}

        if type(hook_data) is str:
            hook_data = json.loads(hook_data)

        project_id_str = hook_data.get('project_id')
        project_id = int(project_id_str)
        project_body = hook_data.get('project')

        if project_body is not None:
            project_name = project_body.get('name')
            call_snyk(project_name, project_id)

        else:
            project_name = "No project name provided"
            call_snyk(project_name, project_id)

        print(f"{project_name} (ID: {project_id}) is being added or reloaded in Snyk.")

        # NOTE: A successful return code makes the API gateway happy
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"Project ID to be added to Snyk": f"{project_id}"}),
        }

    # Catastrophic failure handler
    except Exception as e:
        print("Caught an exception")
        the_trace = traceback.format_exc()

        print(f"exception occurred...\n {the_trace}")

        raise e
