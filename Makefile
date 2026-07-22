.PHONY: all build release clean run

CMAKE_FLAGS ?= -DNSLITE_USE_SYSTEM_LIBS=OFF

all: build

build:
	@mkdir -p build
	@cd build && cmake $(CMAKE_FLAGS) -DCMAKE_BUILD_TYPE=Debug .. && cmake --build .

release:
	@mkdir -p build
	@cd build && cmake $(CMAKE_FLAGS) -DCMAKE_BUILD_TYPE=Release .. && cmake --build .

clean:
	@rm -rf build

run: build
	./build/nsl .
