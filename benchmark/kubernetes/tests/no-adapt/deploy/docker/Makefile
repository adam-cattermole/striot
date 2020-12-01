in_srcs := $(wildcard **/*.hs) $(wildcard **/Dockerfile)


.PHONY: all
all: build install


.PHONY: build
build: $(in_srcs)
	docker build -t adamcattermole/striot-node1:latest node1
	docker build -t adamcattermole/striot-node2:latest node2
	docker build -t adamcattermole/striot-node3:latest node3
	docker build -t adamcattermole/striot-node4:latest node4
	docker build -t adamcattermole/striot-manage:latest manage-sender


.PHONY: install
install: build
	docker push adamcattermole/striot-node1:latest
	docker push adamcattermole/striot-node2:latest
	docker push adamcattermole/striot-node3:latest
	docker push adamcattermole/striot-node4:latest
	docker push adamcattermole/striot-manage:latest
