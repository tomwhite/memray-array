PROFILES_DIR    = profiles
FLAMEGRAPHS_DIR = flamegraphs

.DELETE_ON_ERROR:
.DEFAULT_GOAL := all

PYTHON_VERSION ?= 3.14
UV_RUN = uv run --python $(PYTHON_VERSION) --isolated --with-requirements

# S3 store prefix — override on the command line or via environment
S3_PREFIX ?= s3://cubed-unittest/mem-array

# ══ Current targets ═══════════════════════════════════════════════════════════
# The actively tracked matrix: local filesystem with the latest zarr-python
# (local store + obstore) and zarrista. These feed the auto-generated tables in
# README.md. When a new zarr-python is released, bump CURRENT_ZARR, add its
# config, regenerate, and promote the outgoing rows into the static "Legacy
# results" table by hand (their flamegraphs are already committed).

CURRENT_ZARR   := 3.3.0
CURRENT_CONFIG := configs/zarr-$(CURRENT_ZARR).txt

CURRENT_PROFILES = \
	$(PROFILES_DIR)/write-local-zarr-$(CURRENT_ZARR)-fsspec-compressed.bin \
	$(PROFILES_DIR)/write-local-zarr-$(CURRENT_ZARR)-fsspec-uncompressed.bin \
	$(PROFILES_DIR)/write-local-zarr-$(CURRENT_ZARR)-obstore-compressed.bin \
	$(PROFILES_DIR)/write-local-zarr-$(CURRENT_ZARR)-obstore-uncompressed.bin \
	$(PROFILES_DIR)/write-local-zarr-$(CURRENT_ZARR)-icechunk-compressed.bin \
	$(PROFILES_DIR)/write-local-zarr-$(CURRENT_ZARR)-icechunk-uncompressed.bin \
	$(PROFILES_DIR)/write-local-zarrista-0.1.0-local-compressed.bin \
	$(PROFILES_DIR)/write-local-zarrista-0.1.0-local-uncompressed.bin \
	$(PROFILES_DIR)/write-local-zarrista-0.1.0-obstore-compressed.bin \
	$(PROFILES_DIR)/write-local-zarrista-0.1.0-obstore-uncompressed.bin \
	$(PROFILES_DIR)/read-local-zarr-$(CURRENT_ZARR)-fsspec-compressed.bin \
	$(PROFILES_DIR)/read-local-zarr-$(CURRENT_ZARR)-fsspec-uncompressed.bin \
	$(PROFILES_DIR)/read-local-zarr-$(CURRENT_ZARR)-obstore-compressed.bin \
	$(PROFILES_DIR)/read-local-zarr-$(CURRENT_ZARR)-obstore-uncompressed.bin \
	$(PROFILES_DIR)/read-local-zarr-$(CURRENT_ZARR)-icechunk-compressed.bin \
	$(PROFILES_DIR)/read-local-zarr-$(CURRENT_ZARR)-icechunk-uncompressed.bin \
	$(PROFILES_DIR)/read-local-zarrista-0.1.0-local-compressed.bin \
	$(PROFILES_DIR)/read-local-zarrista-0.1.0-local-uncompressed.bin \
	$(PROFILES_DIR)/read-local-zarrista-0.1.0-obstore-compressed.bin \
	$(PROFILES_DIR)/read-local-zarrista-0.1.0-obstore-uncompressed.bin

# Read profiles depend on the corresponding write (data must exist first).
# Uses explicit rules (not pattern rules) so Make merges prerequisites correctly.
define LOCAL_READ_WRITE_DEP
$(PROFILES_DIR)/read-local-$(1).bin: $(PROFILES_DIR)/write-local-$(1).bin
endef

CURRENT_PAIRS = \
	zarr-$(CURRENT_ZARR)-fsspec-compressed \
	zarr-$(CURRENT_ZARR)-fsspec-uncompressed \
	zarr-$(CURRENT_ZARR)-obstore-compressed \
	zarr-$(CURRENT_ZARR)-obstore-uncompressed \
	zarr-$(CURRENT_ZARR)-icechunk-compressed \
	zarr-$(CURRENT_ZARR)-icechunk-uncompressed \
	zarrista-0.1.0-local-compressed \
	zarrista-0.1.0-local-uncompressed \
	zarrista-0.1.0-obstore-compressed \
	zarrista-0.1.0-obstore-uncompressed
$(foreach p,$(CURRENT_PAIRS),$(eval $(call LOCAL_READ_WRITE_DEP,$(p))))

# latest zarr-python — local store — local
$(PROFILES_DIR)/write-local-zarr-$(CURRENT_ZARR)-fsspec-compressed.bin: memray-array.py $(CURRENT_CONFIG)
	$(UV_RUN) $(CURRENT_CONFIG) memray-array.py write

$(PROFILES_DIR)/write-local-zarr-$(CURRENT_ZARR)-fsspec-uncompressed.bin: memray-array.py $(CURRENT_CONFIG)
	$(UV_RUN) $(CURRENT_CONFIG) memray-array.py write --no-compress

$(PROFILES_DIR)/read-local-zarr-$(CURRENT_ZARR)-fsspec-compressed.bin: memray-array.py $(CURRENT_CONFIG)
	$(UV_RUN) $(CURRENT_CONFIG) memray-array.py read

$(PROFILES_DIR)/read-local-zarr-$(CURRENT_ZARR)-fsspec-uncompressed.bin: memray-array.py $(CURRENT_CONFIG)
	$(UV_RUN) $(CURRENT_CONFIG) memray-array.py read --no-compress

# latest zarr-python — obstore — local
$(PROFILES_DIR)/write-local-zarr-$(CURRENT_ZARR)-obstore-compressed.bin: memray-array.py $(CURRENT_CONFIG)
	$(UV_RUN) $(CURRENT_CONFIG) memray-array.py write --library obstore

$(PROFILES_DIR)/write-local-zarr-$(CURRENT_ZARR)-obstore-uncompressed.bin: memray-array.py $(CURRENT_CONFIG)
	$(UV_RUN) $(CURRENT_CONFIG) memray-array.py write --no-compress --library obstore

$(PROFILES_DIR)/read-local-zarr-$(CURRENT_ZARR)-obstore-compressed.bin: memray-array.py $(CURRENT_CONFIG)
	$(UV_RUN) $(CURRENT_CONFIG) memray-array.py read --library obstore

$(PROFILES_DIR)/read-local-zarr-$(CURRENT_ZARR)-obstore-uncompressed.bin: memray-array.py $(CURRENT_CONFIG)
	$(UV_RUN) $(CURRENT_CONFIG) memray-array.py read --no-compress --library obstore

# latest zarr-python — icechunk — local
# Each variant gets its own clean prefix so compressed/uncompressed don't clobber
# each other in a shared repo (reads run after all writes).
$(PROFILES_DIR)/write-local-zarr-$(CURRENT_ZARR)-icechunk-compressed.bin: memray-array.py $(CURRENT_CONFIG)
	$(UV_RUN) $(CURRENT_CONFIG) memray-array.py write --library icechunk --store-prefix data/icechunk-compressed

$(PROFILES_DIR)/write-local-zarr-$(CURRENT_ZARR)-icechunk-uncompressed.bin: memray-array.py $(CURRENT_CONFIG)
	$(UV_RUN) $(CURRENT_CONFIG) memray-array.py write --no-compress --library icechunk --store-prefix data/icechunk-uncompressed

$(PROFILES_DIR)/read-local-zarr-$(CURRENT_ZARR)-icechunk-compressed.bin: memray-array.py $(CURRENT_CONFIG)
	$(UV_RUN) $(CURRENT_CONFIG) memray-array.py read --library icechunk --store-prefix data/icechunk-compressed

$(PROFILES_DIR)/read-local-zarr-$(CURRENT_ZARR)-icechunk-uncompressed.bin: memray-array.py $(CURRENT_CONFIG)
	$(UV_RUN) $(CURRENT_CONFIG) memray-array.py read --no-compress --library icechunk --store-prefix data/icechunk-uncompressed

# zarrista 0.1.0 — local
$(PROFILES_DIR)/write-local-zarrista-0.1.0-local-compressed.bin: memray-array.py configs/zarrista-0.1.0.txt
	$(UV_RUN) configs/zarrista-0.1.0.txt memray-array.py write --library zarrista

$(PROFILES_DIR)/write-local-zarrista-0.1.0-local-uncompressed.bin: memray-array.py configs/zarrista-0.1.0.txt
	$(UV_RUN) configs/zarrista-0.1.0.txt memray-array.py write --no-compress --library zarrista

$(PROFILES_DIR)/read-local-zarrista-0.1.0-local-compressed.bin: memray-array.py configs/zarrista-0.1.0.txt
	$(UV_RUN) configs/zarrista-0.1.0.txt memray-array.py read --library zarrista

$(PROFILES_DIR)/read-local-zarrista-0.1.0-local-uncompressed.bin: memray-array.py configs/zarrista-0.1.0.txt
	$(UV_RUN) configs/zarrista-0.1.0.txt memray-array.py read --no-compress --library zarrista

# zarrista 0.1.0 — obstore (async) — local
$(PROFILES_DIR)/write-local-zarrista-0.1.0-obstore-compressed.bin: memray-array.py configs/zarrista-0.1.0.txt
	$(UV_RUN) configs/zarrista-0.1.0.txt memray-array.py write --library zarrista-obstore

$(PROFILES_DIR)/write-local-zarrista-0.1.0-obstore-uncompressed.bin: memray-array.py configs/zarrista-0.1.0.txt
	$(UV_RUN) configs/zarrista-0.1.0.txt memray-array.py write --no-compress --library zarrista-obstore

$(PROFILES_DIR)/read-local-zarrista-0.1.0-obstore-compressed.bin: memray-array.py configs/zarrista-0.1.0.txt
	$(UV_RUN) configs/zarrista-0.1.0.txt memray-array.py read --library zarrista-obstore

$(PROFILES_DIR)/read-local-zarrista-0.1.0-obstore-uncompressed.bin: memray-array.py configs/zarrista-0.1.0.txt
	$(UV_RUN) configs/zarrista-0.1.0.txt memray-array.py read --no-compress --library zarrista-obstore

# ══ Legacy targets ════════════════════════════════════════════════════════════
# Older library versions, kept for reproducibility. Their results are frozen in
# the static "Legacy results" table in README.md and are NOT part of the default
# build (so `make` never rebuilds their committed flamegraphs). Run explicitly
# with `make legacy-profiles`.

LEGACY_PROFILES = \
	$(PROFILES_DIR)/write-local-zarr-2.18.7-fsspec-compressed.bin \
	$(PROFILES_DIR)/write-local-zarr-2.18.7-fsspec-uncompressed.bin \
	$(PROFILES_DIR)/write-local-zarr-3.0.6-fsspec-compressed.bin \
	$(PROFILES_DIR)/write-local-zarr-3.0.6-fsspec-uncompressed.bin \
	$(PROFILES_DIR)/write-local-zarr-3.0.8-fsspec-compressed.bin \
	$(PROFILES_DIR)/write-local-zarr-3.0.8-fsspec-uncompressed.bin \
	$(PROFILES_DIR)/write-local-zarr-3.0.8-obstore-compressed.bin \
	$(PROFILES_DIR)/write-local-zarr-3.0.8-obstore-uncompressed.bin \
	$(PROFILES_DIR)/read-local-zarr-2.18.7-fsspec-compressed.bin \
	$(PROFILES_DIR)/read-local-zarr-2.18.7-fsspec-uncompressed.bin \
	$(PROFILES_DIR)/read-local-zarr-3.0.6-fsspec-compressed.bin \
	$(PROFILES_DIR)/read-local-zarr-3.0.6-fsspec-uncompressed.bin \
	$(PROFILES_DIR)/read-local-zarr-3.0.8-fsspec-compressed.bin \
	$(PROFILES_DIR)/read-local-zarr-3.0.8-fsspec-uncompressed.bin \
	$(PROFILES_DIR)/read-local-zarr-3.0.8-obstore-compressed.bin \
	$(PROFILES_DIR)/read-local-zarr-3.0.8-obstore-uncompressed.bin

LEGACY_PAIRS = \
	zarr-2.18.7-fsspec-compressed \
	zarr-2.18.7-fsspec-uncompressed \
	zarr-3.0.6-fsspec-compressed \
	zarr-3.0.6-fsspec-uncompressed \
	zarr-3.0.8-fsspec-compressed \
	zarr-3.0.8-fsspec-uncompressed \
	zarr-3.0.8-obstore-compressed \
	zarr-3.0.8-obstore-uncompressed
$(foreach p,$(LEGACY_PAIRS),$(eval $(call LOCAL_READ_WRITE_DEP,$(p))))

# zarr 2.18.7 — fsspec — local
$(PROFILES_DIR)/write-local-zarr-2.18.7-fsspec-compressed.bin: memray-array.py configs/zarr-2.18.7.txt
	$(UV_RUN) configs/zarr-2.18.7.txt memray-array.py write

$(PROFILES_DIR)/write-local-zarr-2.18.7-fsspec-uncompressed.bin: memray-array.py configs/zarr-2.18.7.txt
	$(UV_RUN) configs/zarr-2.18.7.txt memray-array.py write --no-compress

$(PROFILES_DIR)/read-local-zarr-2.18.7-fsspec-compressed.bin: memray-array.py configs/zarr-2.18.7.txt
	$(UV_RUN) configs/zarr-2.18.7.txt memray-array.py read

$(PROFILES_DIR)/read-local-zarr-2.18.7-fsspec-uncompressed.bin: memray-array.py configs/zarr-2.18.7.txt
	$(UV_RUN) configs/zarr-2.18.7.txt memray-array.py read --no-compress

# zarr 3.0.6 — fsspec — local
$(PROFILES_DIR)/write-local-zarr-3.0.6-fsspec-compressed.bin: memray-array.py configs/zarr-3.0.6.txt
	$(UV_RUN) configs/zarr-3.0.6.txt memray-array.py write

$(PROFILES_DIR)/write-local-zarr-3.0.6-fsspec-uncompressed.bin: memray-array.py configs/zarr-3.0.6.txt
	$(UV_RUN) configs/zarr-3.0.6.txt memray-array.py write --no-compress

$(PROFILES_DIR)/read-local-zarr-3.0.6-fsspec-compressed.bin: memray-array.py configs/zarr-3.0.6.txt
	$(UV_RUN) configs/zarr-3.0.6.txt memray-array.py read

$(PROFILES_DIR)/read-local-zarr-3.0.6-fsspec-uncompressed.bin: memray-array.py configs/zarr-3.0.6.txt
	$(UV_RUN) configs/zarr-3.0.6.txt memray-array.py read --no-compress

# zarr 3.0.8 — fsspec — local
$(PROFILES_DIR)/write-local-zarr-3.0.8-fsspec-compressed.bin: memray-array.py configs/zarr-3.0.8.txt
	$(UV_RUN) configs/zarr-3.0.8.txt memray-array.py write

$(PROFILES_DIR)/write-local-zarr-3.0.8-fsspec-uncompressed.bin: memray-array.py configs/zarr-3.0.8.txt
	$(UV_RUN) configs/zarr-3.0.8.txt memray-array.py write --no-compress

$(PROFILES_DIR)/read-local-zarr-3.0.8-fsspec-compressed.bin: memray-array.py configs/zarr-3.0.8.txt
	$(UV_RUN) configs/zarr-3.0.8.txt memray-array.py read

$(PROFILES_DIR)/read-local-zarr-3.0.8-fsspec-uncompressed.bin: memray-array.py configs/zarr-3.0.8.txt
	$(UV_RUN) configs/zarr-3.0.8.txt memray-array.py read --no-compress

# zarr 3.0.8 — obstore — local
$(PROFILES_DIR)/write-local-zarr-3.0.8-obstore-compressed.bin: memray-array.py configs/zarr-3.0.8.txt
	$(UV_RUN) configs/zarr-3.0.8.txt memray-array.py write --library obstore

$(PROFILES_DIR)/write-local-zarr-3.0.8-obstore-uncompressed.bin: memray-array.py configs/zarr-3.0.8.txt
	$(UV_RUN) configs/zarr-3.0.8.txt memray-array.py write --no-compress --library obstore

$(PROFILES_DIR)/read-local-zarr-3.0.8-obstore-compressed.bin: memray-array.py configs/zarr-3.0.8.txt
	$(UV_RUN) configs/zarr-3.0.8.txt memray-array.py read --library obstore

$(PROFILES_DIR)/read-local-zarr-3.0.8-obstore-uncompressed.bin: memray-array.py configs/zarr-3.0.8.txt
	$(UV_RUN) configs/zarr-3.0.8.txt memray-array.py read --no-compress --library obstore

# ── s3 profiles (legacy) ──────────────────────────────────────────────────────
# obstore's buffer-copy profile is filesystem-independent (local == S3), so S3
# is not part of the current matrix. These rules remain for reproducibility.
# Run with: make s3-profiles S3_PREFIX=s3://your-bucket/mem-array
# Requires AWS credentials in the environment.

S3_PROFILES = \
	$(PROFILES_DIR)/write-s3-zarr-2.18.7-fsspec-compressed.bin \
	$(PROFILES_DIR)/write-s3-zarr-2.18.7-fsspec-uncompressed.bin \
	$(PROFILES_DIR)/write-s3-zarr-3.0.6-fsspec-compressed.bin \
	$(PROFILES_DIR)/write-s3-zarr-3.0.6-fsspec-uncompressed.bin \
	$(PROFILES_DIR)/write-s3-zarr-3.0.8-obstore-compressed.bin \
	$(PROFILES_DIR)/write-s3-zarr-3.0.8-obstore-uncompressed.bin \
	$(PROFILES_DIR)/read-s3-zarr-2.18.7-fsspec-compressed.bin \
	$(PROFILES_DIR)/read-s3-zarr-2.18.7-fsspec-uncompressed.bin \
	$(PROFILES_DIR)/read-s3-zarr-3.0.6-fsspec-compressed.bin \
	$(PROFILES_DIR)/read-s3-zarr-3.0.6-fsspec-uncompressed.bin \
	$(PROFILES_DIR)/read-s3-zarr-3.0.8-obstore-compressed.bin \
	$(PROFILES_DIR)/read-s3-zarr-3.0.8-obstore-uncompressed.bin

S3_PAIRS = \
	zarr-2.18.7-fsspec-compressed \
	zarr-2.18.7-fsspec-uncompressed \
	zarr-3.0.6-fsspec-compressed \
	zarr-3.0.6-fsspec-uncompressed \
	zarr-3.0.8-obstore-compressed \
	zarr-3.0.8-obstore-uncompressed

define S3_READ_WRITE_DEP
$(PROFILES_DIR)/read-s3-$(1).bin: $(PROFILES_DIR)/write-s3-$(1).bin
endef
$(foreach p,$(S3_PAIRS),$(eval $(call S3_READ_WRITE_DEP,$(p))))

# zarr 2.18.7 — fsspec — s3
$(PROFILES_DIR)/write-s3-zarr-2.18.7-fsspec-compressed.bin: memray-array.py configs/zarr-2.18.7.txt
	$(UV_RUN) configs/zarr-2.18.7.txt memray-array.py write --store-prefix=$(S3_PREFIX)

$(PROFILES_DIR)/write-s3-zarr-2.18.7-fsspec-uncompressed.bin: memray-array.py configs/zarr-2.18.7.txt
	$(UV_RUN) configs/zarr-2.18.7.txt memray-array.py write --no-compress --store-prefix=$(S3_PREFIX)

$(PROFILES_DIR)/read-s3-zarr-2.18.7-fsspec-compressed.bin: memray-array.py configs/zarr-2.18.7.txt
	$(UV_RUN) configs/zarr-2.18.7.txt memray-array.py read --store-prefix=$(S3_PREFIX)

$(PROFILES_DIR)/read-s3-zarr-2.18.7-fsspec-uncompressed.bin: memray-array.py configs/zarr-2.18.7.txt
	$(UV_RUN) configs/zarr-2.18.7.txt memray-array.py read --no-compress --store-prefix=$(S3_PREFIX)

# zarr 3.0.6 — fsspec — s3
$(PROFILES_DIR)/write-s3-zarr-3.0.6-fsspec-compressed.bin: memray-array.py configs/zarr-3.0.6.txt
	$(UV_RUN) configs/zarr-3.0.6.txt memray-array.py write --store-prefix=$(S3_PREFIX)

$(PROFILES_DIR)/write-s3-zarr-3.0.6-fsspec-uncompressed.bin: memray-array.py configs/zarr-3.0.6.txt
	$(UV_RUN) configs/zarr-3.0.6.txt memray-array.py write --no-compress --store-prefix=$(S3_PREFIX)

$(PROFILES_DIR)/read-s3-zarr-3.0.6-fsspec-compressed.bin: memray-array.py configs/zarr-3.0.6.txt
	$(UV_RUN) configs/zarr-3.0.6.txt memray-array.py read --store-prefix=$(S3_PREFIX)

$(PROFILES_DIR)/read-s3-zarr-3.0.6-fsspec-uncompressed.bin: memray-array.py configs/zarr-3.0.6.txt
	$(UV_RUN) configs/zarr-3.0.6.txt memray-array.py read --no-compress --store-prefix=$(S3_PREFIX)

# zarr 3.0.8 — obstore — s3
$(PROFILES_DIR)/write-s3-zarr-3.0.8-obstore-compressed.bin: memray-array.py configs/zarr-3.0.8.txt
	$(UV_RUN) configs/zarr-3.0.8.txt memray-array.py write --library obstore --store-prefix=$(S3_PREFIX)

$(PROFILES_DIR)/write-s3-zarr-3.0.8-obstore-uncompressed.bin: memray-array.py configs/zarr-3.0.8.txt
	$(UV_RUN) configs/zarr-3.0.8.txt memray-array.py write --no-compress --library obstore --store-prefix=$(S3_PREFIX)

$(PROFILES_DIR)/read-s3-zarr-3.0.8-obstore-compressed.bin: memray-array.py configs/zarr-3.0.8.txt
	$(UV_RUN) configs/zarr-3.0.8.txt memray-array.py read --library obstore --store-prefix=$(S3_PREFIX)

$(PROFILES_DIR)/read-s3-zarr-3.0.8-obstore-uncompressed.bin: memray-array.py configs/zarr-3.0.8.txt
	$(UV_RUN) configs/zarr-3.0.8.txt memray-array.py read --no-compress --library obstore --store-prefix=$(S3_PREFIX)

# ══ Flamegraphs and tables ════════════════════════════════════════════════════
# Only the current profiles feed the default build, so `make` never touches the
# committed legacy/S3 flamegraphs.

BIN  := $(foreach f,$(CURRENT_PROFILES),$(wildcard $(f)))
HTML := $(patsubst $(PROFILES_DIR)/%.bin,$(FLAMEGRAPHS_DIR)/%.bin.html,$(BIN))

$(FLAMEGRAPHS_DIR)/%.bin.html: $(PROFILES_DIR)/%.bin
	uv run --python $(PYTHON_VERSION) --isolated --with memray python -m memray flamegraph --temporal -f -o $@ $<

all: flamegraphs table

flamegraphs: $(HTML)

# Regenerate the current-results tables in README.md from the current profiles.
# Flamegraph links default to the GitHub Pages URLs; override for local links
# with `make table FLAMEGRAPH_BASE=flamegraphs`.
export FLAMEGRAPH_BASE
table: generate_table.py
	uv run --python $(PYTHON_VERSION) --isolated python generate_table.py

current-profiles: $(CURRENT_PROFILES)

legacy-profiles: $(LEGACY_PROFILES)

s3-profiles: $(S3_PROFILES)

.PHONY: all flamegraphs table current-profiles legacy-profiles s3-profiles clean

clean:
	rm -f $(HTML)
