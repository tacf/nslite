.PHONY: all build release clean run

all: build

build:
	@mkdir -p build
	@cd build && cmake -DCMAKE_BUILD_TYPE=Debug .. && cmake --build .

release:
	@mkdir -p build
	@cd build && cmake -DCMAKE_BUILD_TYPE=Release .. && cmake --build .

clean:
	@rm -rf build

run: build
	./build/lite .
