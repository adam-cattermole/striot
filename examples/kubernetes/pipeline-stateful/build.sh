repo=adamcattermole
prefix=striot-
src=src
link=link
sink=sink
manage=manage
ver=latest
src_full=$repo/$prefix$src:$ver
link_full=$repo/$prefix$link:$ver
sink_full=$repo/$prefix$sink:$ver
manage_full=$repo/$prefix$manage:$ver

docker build $src/ -t $src_full
docker push $src_full 
docker build $link/ -t $link_full
docker push $link_full
docker build $sink/ -t $sink_full 
docker push $sink_full
docker build $manage/ -t $manage_full
docker push $manage_full


