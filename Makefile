# Makefile - Generate FeedKit docs

w := $(shell echo $(workspace))
scheme := FeedKit

docs:
ifdef w
	jazzy -x -workspace,$(w),-scheme,$(scheme) \
		--author "Michael Nisi" \
		--author_url https://troubled.pro
else
	@echo "Which workspace?"
endif

.PHONY: clean
clean:
	rm -rf docs
