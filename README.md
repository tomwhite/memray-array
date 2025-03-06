# memray-array

Measuring memory usage of array storage operations using memray.

In an ideal world array storage operations would be zero-copy, but many libraries do not achieve this in practice. The scripts here measure what the actual empirical behaviour is across different filesystems (local/cloud), compression settings, and Zarr versions.

## Summary

The workload is simple: create a random 100MB NumPy array and write it to Zarr storage in a single chunk. Then (in a separate process) read it back from storage into a new NumPy array.

* Writes with no compression incur a single buffer copy, *except* for Zarr v2 writing to the local filesystem. (This shows that zero copy is possible, at least.)
* Writes with compression incur a second buffer copy, since implementations first write the compressed bytes into another buffer, which has to be around the size of the uncompressed bytes (since it is not known in advance how compressible the original is).
* Reads with no compression incur a single copy from local files, but two copies from S3. This seems to be because the S3 libraries read lots of small blocks then join them into a larger one, whereas local files can be read in one go into a single buffer. 
* Reads with compression incur two buffer copies, *except* for Zarr v2 reading from the local filesystem.

It would seem there is scope to reduce the number of copies in some of these cases.

### Writes

Number of extra copies needed to write an array to storage using Zarr. (Links are to memray flamegraphs.)

| Filesystem | Library | Zarr version | Uncompressed                                                       | Compressed                                                       |
|------------|---------|--------------|--------------------------------------------------------------------|------------------------------------------------------------------|
| Local      | fsspec  | v2           | [0](flamegraphs/write-local-zarr-v2-fsspec-uncompressed.bin.html)  | [2](flamegraphs/write-local-zarr-v2-fsspec-compressed.bin.html)  |
|            |         | v3           | [1](flamegraphs/write-local-zarr-v3-fsspec-uncompressed.bin.html)  | [2](flamegraphs/write-local-zarr-v3-fsspec-compressed.bin.html)  |
|            | obstore | v3           | [1](flamegraphs/write-local-zarr-v3-obstore-uncompressed.bin.html) | [2](flamegraphs/write-local-zarr-v3-obstore-compressed.bin.html) |
| S3         | fsspec  | v2           | [1](flamegraphs/write-s3-zarr-v2-fsspec-uncompressed.bin.html)     | [2](flamegraphs/write-s3-zarr-v2-fsspec-compressed.bin.html)     |
|            |         | v3           | [1](flamegraphs/write-s3-zarr-v3-fsspec-uncompressed.bin.html)     | [2](flamegraphs/write-s3-zarr-v3-fsspec-compressed.bin.html)     |

### Reads

Number of extra copies needed to read an array from storage using Zarr. (Links are to memray flamegraphs.)

| Filesystem | Library | Zarr version | Uncompressed                                                      | Compressed                                                      |
|------------|---------|--------------|-------------------------------------------------------------------|-----------------------------------------------------------------|
| Local      | fsspec  | v2           | [1](flamegraphs/read-local-zarr-v2-fsspec-uncompressed.bin.html)  | [1](flamegraphs/read-local-zarr-v2-fsspec-compressed.bin.html)  |
|            |         | v3           | [1](flamegraphs/read-local-zarr-v3-fsspec-uncompressed.bin.html)  | [2](flamegraphs/read-local-zarr-v3-fsspec-compressed.bin.html)  |
|            | obstore | v3           | [1](flamegraphs/read-local-zarr-v3-obstore-uncompressed.bin.html) | [2](flamegraphs/read-local-zarr-v3-obstore-compressed.bin.html) |
| S3         | fsspec  | v2           | [2](flamegraphs/read-s3-zarr-v2-fsspec-uncompressed.bin.html)     | [2](flamegraphs/read-s3-zarr-v2-fsspec-compressed.bin.html)     |
|            |         | v3           | [2](flamegraphs/read-s3-zarr-v3-fsspec-uncompressed.bin.html)     | [2](flamegraphs/read-s3-zarr-v3-fsspec-compressed.bin.html)     |

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

pip install -U 'git+https://github.com/kylebarron/zarr-python.git@kyle/object-store#egg=zarr'
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
```


### Memray flamegraphs

```shell
mkdir -p flamegraphs
(cd profiles; for f in $(ls *.bin); do echo $f; python -m memray flamegraph --temporal -f -o ../flamegraphs/$f.html $f; done)
```
