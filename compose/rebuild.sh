#stop container
docker compose down

#rebuild container

docker compose up --build -d

docker logs -f moodle-web

