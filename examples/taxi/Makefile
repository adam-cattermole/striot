.PHONY: q1
q1: docker-taxi-q1/node*/node*.hs docker-taxi-q1/node*/Dockerfile docker-taxi-q1/docker-compose.yml image
	@echo "Starting taxi query 1..."
	@docker-compose -f docker-taxi-q1/docker-compose.yml up --build

.PHONY: q2
q2: docker-taxi-q2/node*/node*.hs docker-taxi-q2/node*/Dockerfile docker-taxi-q2/docker-compose.yml image
	@echo "Starting taxi query 2..."
	@docker-compose -f docker-taxi-q2/docker-compose.yml up --build

.PHONY: image
image: taxi-base/Dockerfile taxi-base/TaxiUtil.hs
	@echo "Building striot/striot-taxi"
	@docker build -t striot/striot-taxi taxi-base

.PHONY: clean
clean:
	@echo "Removing striot-base/striot-taxi"
	@if [ -n "$$(docker images -q $(prefix)/striot-taxi)" ]; then \
		docker rmi $(prefix)/striot-taxi; \
	fi
