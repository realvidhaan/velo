.PHONY: build app run test clean

# Compile the package (fast check that everything builds).
build:
	swift build

# Assemble a signed, runnable FlowClone.app.
app:
	./Scripts/build-app.sh debug

# Build and launch the app.
run: app
	@echo "==> Launching FlowClone.app"
	@open build/FlowClone.app

# Run the unit tests (pure-logic targets).
test:
	swift test

clean:
	swift package clean
	rm -rf build
