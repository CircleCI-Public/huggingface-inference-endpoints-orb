#!/bin/sh

# check if webhook body is provided and it is not empty or null or not equal to {}
if [ -z "$WEBHOOK_BODY" ] || [ "$WEBHOOK_BODY" = "null" ] || [ "$WEBHOOK_BODY" = "{}" ]; then
  echo "Webhook body is empty or null"
  exit 1
fi
# exit if action is not update and scope is not repo.content
if [ "$(echo "$WEBHOOK_BODY" | jq -r '.event.action')" != "update" ] || [ "$(echo "$WEBHOOK_BODY" | jq -r '.event.scope')" != "repo.content" ]; then
  echo "Webhook body action is not update or scope is not repo.content"
  exit 0
fi

# get new sha and old sha from webhook body for given branch
OLD_SHA=$(echo "$WEBHOOK_BODY" | jq -r --arg branch "$BRANCH_NAME" '.updatedRefs[] | select(.ref == "refs/heads/\($branch)") | .oldSha')
NEW_SHA=$(echo "$WEBHOOK_BODY" | jq -r --arg branch "$BRANCH_NAME" '.updatedRefs[] | select(.ref == "refs/heads/\($branch)") | .newSha')
echo "Old revision: $OLD_SHA"
echo "New revision: $NEW_SHA"

# get current revision from inference endpoint
GET_INFERENCE_ENDPOINT_API_RESPONSE=$(curl -s -X GET "https://api.endpoints.huggingface.cloud/v2/endpoint/$ORGANIZATION_NAME/$INFERENCE_ENDPOINT_NAME" \
  -H "Authorization: Bearer $HF_TOKEN" \
  -H "Content-Type: application/json")

if echo "$GET_INFERENCE_ENDPOINT_API_RESPONSE" | jq -e '.error' > /dev/null; then
  echo "Error getting inference endpoint: $(echo "$GET_INFERENCE_ENDPOINT_API_RESPONSE" | jq -r '.error')"
  exit 1
fi

CURRENT_REVISION=$(echo "$GET_INFERENCE_ENDPOINT_API_RESPONSE" | jq -r '.model.revision')
echo "Current revision is $CURRENT_REVISION"

if [ "$CURRENT_REVISION" = "$NEW_SHA" ]; then
  echo "Inference endpoint is up to date with the revision $CURRENT_REVISION"
  exit 0
fi
MODEL_REPOSITORY=$(echo "$GET_INFERENCE_ENDPOINT_API_RESPONSE" | jq -r '.model.repository')
echo "Model repository is $MODEL_REPOSITORY"

# update inference endpoint with new revision
echo "Updating inference endpoint $INFERENCE_ENDPOINT_NAME with new revision $NEW_SHA from revision $CURRENT_REVISION from repository $MODEL_REPOSITORY"
UPDATE_ENDPOINT_API_RESPONSE=$(curl -s -f -X PUT "https://api.endpoints.huggingface.cloud/v2/endpoint/$ORGANIZATION_NAME/$INFERENCE_ENDPOINT_NAME" \
  -H "Authorization: Bearer $HF_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"model\":{\"repository\":\"$MODEL_REPOSITORY\",\"revision\":\"$NEW_SHA\"}}")

if echo "$UPDATE_ENDPOINT_API_RESPONSE" | jq -e '.error' > /dev/null; then
  echo "Error updating inference endpoint: $(echo "$UPDATE_ENDPOINT_API_RESPONSE" | jq -r '.error')"
  exit 1
fi

echo "Inference endpoint update triggered successfully!!!"
echo "Check the status of the update at https://ui.endpoints.huggingface.co/$ORGANIZATION_NAME/endpoints/$INFERENCE_ENDPOINT_NAME"
exit 0
