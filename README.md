# pandoc-rest-api
REST API for pandoc document conversion

Build and run
```
docker compose up -d --build
```
Usage example:
```
curl -X POST -F "file=@input.md" -F "output_filename=document.pdf" -o document.pdf http://localhost:35000/convert
```

amd64 docker image: https://hub.docker.com/repository/docker/theapu/pandoc-api/general
