TAG="v1.0"
ACCOUNT="jazevedo6"
docker build -t "$ACCOUNT/load_interference:$TAG" .
docker push "$ACCOUNT/load_interference:$TAG"
