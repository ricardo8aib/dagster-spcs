# Define tags for each image
POSTGRES_TAG="postgres:latest"
USER_CODE_TAG="user-code-image:latest"
WEBSERVER_TAG="webserver-image:latest"
DAEMON_TAG="daemon-image:latest"

# Define the image repositoryu url variable
IMAGE_REGISTRY="uxjcdsw-aab99587.registry.snowflakecomputing.com"
IMAGE_REPO_URL="uxjcdsw-aab99587.registry.snowflakecomputing.com/prod_analytics/landing/dagster_university_repo"

# Define Snowflake User
SNOWFLAKE_USER="raibarra"

# Build the images
docker build --platform linux/amd64 -t $POSTGRES_TAG -f ./Dockerfile_postgres .
docker build --platform linux/amd64 -t $USER_CODE_TAG -f ./Dockerfile_user_code .
docker build --platform linux/amd64 -t $WEBSERVER_TAG -f ./Dockerfile_dagster .
docker build --platform linux/amd64 -t $DAEMON_TAG -f ./Dockerfile_dagster .

# Tag each Docker image
docker tag "$POSTGRES_TAG" "$IMAGE_REPO_URL/$POSTGRES_TAG"
docker tag "$USER_CODE_TAG" "$IMAGE_REPO_URL/$USER_CODE_TAG"
docker tag "$WEBSERVER_TAG" "$IMAGE_REPO_URL/$WEBSERVER_TAG"
docker tag "$DAEMON_TAG" "$IMAGE_REPO_URL/$DAEMON_TAG"

# Login
docker login $IMAGE_REGISTRY -u $SNOWFLAKE_USER

# Push images
docker push "$IMAGE_REPO_URL/$POSTGRES_TAG"
docker push "$IMAGE_REPO_URL/$USER_CODE_TAG"
docker push "$IMAGE_REPO_URL/$WEBSERVER_TAG"
docker push "$IMAGE_REPO_URL/$DAEMON_TAG"
