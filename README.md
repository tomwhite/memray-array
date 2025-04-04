# memray-array

Measuring memory usage of Zarr array storage operations using memray.

In an ideal world array storage operations would be zero-copy, but many libraries do not achieve this in practice. The scripts here measure what the actual empirical behaviour is across different filesystems (local/cloud), Zarr stores (local/s3fs/obstore), compression settings (using numcodecs), and Zarr Python versions (v2/v3).

**TL;DR: we need to fix**
* ~~https://github.com/zarr-developers/zarr-python/pull/2944~~ (fixed)
* https://github.com/zarr-developers/zarr-python/issues/2925
* ~~https://github.com/zarr-developers/numcodecs/issues/717~~ (fixed in https://github.com/zarr-developers/numcodecs/pull/656)
* https://github.com/zarr-developers/zarr-python/issues/2904

## Summary

The workload is simple: create a random 100MB NumPy array and write it to Zarr storage in a single chunk. Then (in a separate process) read it back from storage into a new NumPy array.

* Writes with no compression incur a single buffer copy, *except* for Zarr v2 writing to the local filesystem. (This shows that zero copy is possible, at least.)
* Writes with compression incur a second buffer copy, since implementations first write the compressed bytes into another buffer, which has to be around the size of the uncompressed bytes (since it is not known in advance how compressible the original is).
* Reads with no compression incur a single copy from local files, but two copies from S3 (except for obstore, which has a single copy). This seems to be because the S3 libraries read lots of small blocks then join them into a larger one, whereas local files can be read in one go into a single buffer. 
* Reads with compression incur two buffer copies, *except* for Zarr v2 reading from the local filesystem.

It would seem there is scope to reduce the number of copies in some of these cases.

### Writes

Number of extra copies needed to write an array to storage using Zarr. (Links are to memray flamegraphs.)

| Filesystem | Store   | Zarr Python version | Uncompressed                                                       | Compressed                                                       |
|------------|---------|--------------|--------------------------------------------------------------------|------------------------------------------------------------------|
| Local      | local   | v2           | [0](http://tomwhite.github.io/memray-array/flamegraphs/write-local-zarr-v2-fsspec-uncompressed.bin.html)  | [2](http://tomwhite.github.io/memray-array/flamegraphs/write-local-zarr-v2-fsspec-compressed.bin.html)  |
|            |         | v3           | [1](http://tomwhite.github.io/memray-array/flamegraphs/write-local-zarr-v3-fsspec-uncompressed.bin.html)  | [2](http://tomwhite.github.io/memray-array/flamegraphs/write-local-zarr-v3-fsspec-compressed.bin.html)  |
|            | obstore | v3           | [1](http://tomwhite.github.io/memray-array/flamegraphs/write-local-zarr-v3-obstore-uncompressed.bin.html) | [2](http://tomwhite.github.io/memray-array/flamegraphs/write-local-zarr-v3-obstore-compressed.bin.html) |
| S3         | s3fs    | v2           | [1](http://tomwhite.github.io/memray-array/flamegraphs/write-s3-zarr-v2-fsspec-uncompressed.bin.html)     | [2](http://tomwhite.github.io/memray-array/flamegraphs/write-s3-zarr-v2-fsspec-compressed.bin.html)     |
|            |         | v3           | [1](http://tomwhite.github.io/memray-array/flamegraphs/write-s3-zarr-v3-fsspec-uncompressed.bin.html)     | [2](http://tomwhite.github.io/memray-array/flamegraphs/write-s3-zarr-v3-fsspec-compressed.bin.html)     |
|            | obstore | v3           | [1](http://tomwhite.github.io/memray-array/flamegraphs/write-s3-zarr-v3-obstore-uncompressed.bin.html)     | [2](http://tomwhite.github.io/memray-array/flamegraphs/write-s3-zarr-v3-obstore-compressed.bin.html)     |

### Reads

Number of extra copies needed to read an array from storage using Zarr. (Links are to memray flamegraphs.)

| Filesystem | Store   | Zarr Python version | Uncompressed                                                      | Compressed                                                      |
|------------|---------|--------------|-------------------------------------------------------------------|-----------------------------------------------------------------|
| Local      | local   | v2           | [1](http://tomwhite.github.io/memray-array/flamegraphs/read-local-zarr-v2-fsspec-uncompressed.bin.html)  | [1](http://tomwhite.github.io/memray-array/flamegraphs/read-local-zarr-v2-fsspec-compressed.bin.html)  |
|            |        | v3           | [1](http://tomwhite.github.io/memray-array/flamegraphs/read-local-zarr-v3-fsspec-uncompressed.bin.html)  | [2](http://tomwhite.github.io/memray-array/flamegraphs/read-local-zarr-v3-fsspec-compressed.bin.html)  |
|            | obstore | v3           | [1](http://tomwhite.github.io/memray-array/flamegraphs/read-local-zarr-v3-obstore-uncompressed.bin.html) | [2](http://tomwhite.github.io/memray-array/flamegraphs/read-local-zarr-v3-obstore-compressed.bin.html) |
| S3         | s3fs    | v2           | [2](http://tomwhite.github.io/memray-array/flamegraphs/read-s3-zarr-v2-fsspec-uncompressed.bin.html)     | [2](http://tomwhite.github.io/memray-array/flamegraphs/read-s3-zarr-v2-fsspec-compressed.bin.html)     |
|            |         | v3           | [2](http://tomwhite.github.io/memray-array/flamegraphs/read-s3-zarr-v3-fsspec-uncompressed.bin.html)     | [2](http://tomwhite.github.io/memray-array/flamegraphs/read-s3-zarr-v3-fsspec-compressed.bin.html)     |
|            | obstore | v3           | [1](http://tomwhite.github.io/memray-array/flamegraphs/read-s3-zarr-v3-obstore-uncompressed.bin.html)     | [2](http://tomwhite.github.io/memray-array/flamegraphs/read-s3-zarr-v3-obstore-compressed.bin.html)     |

## Discussion

This delves into what is happening for the different code paths, and suggests some remedies to reduce the number of buffer copies.

### Writes

* **Local uncompressed writes (v2 only)**  - actual copies 0, desired copies 0
    * This is the only zero-copy case. The numpy array is passed directly to the file's [`write()`](https://docs.python.org/3/library/io.html#io.BufferedIOBase.write) method (in [`DirectoryStore`](https://github.com/zarr-developers/zarr-python/blob/support/v2/zarr/storage.py#L1111-L1112)), and since arrays implement the [buffer protocol](https://docs.python.org/3/c-api/buffer.html), no copy is made.
* **S3 uncompressed writes (v2 only)** - actual copies 1, desired copies 0
    * A copy of the numpy array is made by this code in fsspec (in `maybe_convert`, called from `FSMap.setitems()`): [`bytes(memoryview(value))`](https://github.com/fsspec/filesystem_spec/blob/199ee82486990a295f744820d4dd2a7180e1c7a6/fsspec/mapping.py#L206).
    * **Remedy**: it might be possible to use the memory view in fsspec and avoid the copy, but it's probably better to focus on improvements to v3 (see below)

* **Uncompressed writes (v3 only)** - actual copies 1, desired copies 0
    * A copy of the numpy array is made by this code (in Zarr's `LocalStore`): [`memoryview(value.as_numpy_array().tobytes())`](https://github.com/zarr-developers/zarr-python/blob/8c24819809b649890cfbe5d27f7f29d77bfa0dd9/src/zarr/storage/_local.py#L57). A similar thing happens in [`FsspecStore`](https://github.com/zarr-developers/zarr-python/blob/8c24819809b649890cfbe5d27f7f29d77bfa0dd9/src/zarr/storage/_fsspec.py#L277) and obstore.
    * **Remedy**: this could be fixed with https://github.com/zarr-developers/zarr-python/issues/2925, so the `value` `Buffer` is exposed via the buffer protocol without making a copy.

* **Compressed writes** - actual copies 2, desired copies 1
    * It is surprising that there are *two* copies, not one, given that the uncompressed case has zero copies (for local v2, at least). What's happening is that the numcodecs blosc compressor is making an extra copy when [it resizes the compressed buffer](https://github.com/zarr-developers/numcodecs/blob/3c933cf19d4d84f2efc5f3a36926d8c569514a90/numcodecs/blosc.pyx#L345). A similar thing happens for lz4 and zstd.
    * **Remedy**: the issue is tracked in numcodecs in https://github.com/zarr-developers/numcodecs/issues/717.


### Reads

* **Local reads (v2 only)**  - actual copies 1, desired copies 0
    * The Zarr Python v2 read pipeline separates reading the bytes from storage, and filling the output array - see [`_process_chunk()`](https://github.com/zarr-developers/zarr-python/blob/support/v2/zarr/core.py#L2012-L2062). So there is necessarily a buffer copy, since the bytes are never read directly into the output array.
    * **Remedy**: Zarr Python v2 is in bugfix mode now so there is no point in trying to change it to make fewer buffer copies. The changes would be quite invasive anyway.

* **Local reads (v3 only), plus obstore local and S3**  - actual copies 1 (2 for compressed), desired copies 0 (1 for compressed)
    * The Zarr Python v3 `CodecPipeline` has a [`read()`](https://github.com/zarr-developers/zarr-python/blob/8c24819809b649890cfbe5d27f7f29d77bfa0dd9/src/zarr/abc/codec.py#L358-L377) method that separates reading the bytes from storage, and filling the output array (just like v2). The [`ByteGetter`](https://github.com/zarr-developers/zarr-python/blob/8c24819809b649890cfbe5d27f7f29d77bfa0dd9/src/zarr/abc/store.py#L453-L456) class has no way of reading directly into an output array.
    * **Remedy**: this could be fixed by https://github.com/zarr-developers/zarr-python/issues/2904, but it is potentially a major change to Zarr's internals

* **S3 reads (s3fs only)**  - actual copies 2, desired copies 0
    * Both the Python asyncio SSL library and aiohttp introduce a buffer copy when reading from S3 (using s3fs).
    * **Remedy**: unclear

### Related issues

* [cubed] Improve memory model by explicitly modelling buffer copies - https://github.com/cubed-dev/cubed/pull/701 (fixed)
* [zarr-python] Codec pipeline memory usage - https://github.com/zarr-developers/zarr-python/issues/2904
* [zarr-python] Add `Buffer.as_buffer_like` method - https://github.com/zarr-developers/zarr-python/issues/2925
* [zarr-python] Avoid memory copy in local store write - https://github.com/zarr-developers/zarr-python/pull/2944 (fixed)
* [numcodecs] Extra memory copies in blosc, lz4, and zstd compress functions - https://github.com/zarr-developers/numcodecs/issues/717 (fixed)
* [numcodecs] Switch `Buffer`s to `memoryview`s - https://github.com/zarr-developers/numcodecs/pull/656 (fixed)

## How to run

Create a new virtual env (for Python 3.11), then run

```shell
pip install -r requirements.txt
```

### Local

```shell
pip install -U 'zarr<3'
python memray-array.py write
python memray-array.py write --no-compress
python memray-array.py read
python memray-array.py read --no-compress

pip install -U 'zarr>3'
python memray-array.py write
python memray-array.py write --no-compress
python memray-array.py read
python memray-array.py read --no-compress

pip install -U 'git+https://github.com/zarr-developers/zarr-python#egg=zarr'
python memray-array.py write --library obstore
python memray-array.py write --no-compress --library obstore
python memray-array.py read --library obstore
python memray-array.py read --no-compress --library obstore
```

### S3

These can take a while to run (unless run from within AWS).

Note: change the URL to an S3 bucket you own and have already created.

```shell
pip install -U 'zarr<3'
python memray-array.py write --store-prefix=s3://cubed-unittest/mem-array
python memray-array.py write --no-compress --store-prefix=s3://cubed-unittest/mem-array
python memray-array.py read --store-prefix=s3://cubed-unittest/mem-array
python memray-array.py read --no-compress --store-prefix=s3://cubed-unittest/mem-array

pip install -U 'zarr>3'
python memray-array.py write --store-prefix=s3://cubed-unittest/mem-array
python memray-array.py write --no-compress --store-prefix=s3://cubed-unittest/mem-array
python memray-array.py read --store-prefix=s3://cubed-unittest/mem-array
python memray-array.py read --no-compress --store-prefix=s3://cubed-unittest/mem-array

pip install -U 'git+https://github.com/zarr-developers/zarr-python#egg=zarr'
export AWS_DEFAULT_REGION=...
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
python memray-array.py write --library obstore --store-prefix=s3://cubed-unittest/mem-array
python memray-array.py write --no-compress --library obstore --store-prefix=s3://cubed-unittest/mem-array
python memray-array.py read --library obstore --store-prefix=s3://cubed-unittest/mem-array
python memray-array.py read --no-compress --library obstore --store-prefix=s3://cubed-unittest/mem-array
```


### Memray flamegraphs

```shell
mkdir -p flamegraphs
(cd profiles; for f in $(ls *.bin); do echo $f; python -m memray flamegraph --temporal -f -o ../flamegraphs/$f.html $f; done)
```

Or just run `make`.
