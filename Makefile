.PHONY: setup build app run test clean

# One-time: create a persistent local code-signing identity so the app keeps
# its Accessibility/Input Monitoring/Microphone permissions across rebuilds.
# Run this once before your first `make run`; you don't need it again.
setup:
	./Scripts/setup-signing.sh

# Compile the package (fast check that everything builds).
build:
	swift build

# Assemble a signed, runnable Velo.app.
app:
	./Scripts/build-app.sh debug

# Build and launch the app.
run: app
	@echo "==> Launching Velo.app"
	@open build/Velo.app

# Run the unit tests (pure-logic targets).
test:
	swift test

clean:
	swift package clean
	rm -rf build
