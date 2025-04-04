VPATH = profiles
BUILDDIR = flamegraphs

BIN := $(wildcard $(VPATH)/*.bin)
HTML := $(patsubst $(VPATH)/%.bin, $(BUILDDIR)/%.bin.html, $(BIN))

all: $(HTML)

$(BUILDDIR)/%.bin.html : %.bin
	python -m memray flamegraph --temporal -f -o $@ $<

clean:
	rm -f $(HTML)