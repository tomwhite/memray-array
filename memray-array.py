import os
from pathlib import Path

import click
import memray
import numpy as np
import obstore
import zarr


@click.group()
def cli():
    Path("profiles").mkdir(parents=True, exist_ok=True)


store_prefix_option = click.option(
    "--store-prefix",
    default="data",
    help="Zarr store prefix, should be a local directory or an object store",
)

compress_option = click.option(
    "--compress/--no-compress", is_flag=True, default=True, help="Enable compression"
)

library_option = click.option(
    "--library",
    default="fsspec",
    type=click.Choice(["fsspec", "obstore"]),
    help="Library to use for file IO",
)


@cli.command()
@store_prefix_option
@compress_option
@library_option
def read(store_prefix, compress, library):
    fs = filesystem(store_prefix)
    zarr_version = find_zarr_version(library)
    compressed = "compressed" if compress else "uncompressed"
    label = f"read-{fs}-zarr-{zarr_version}-{library}-{compressed}"
    store = f"{store_prefix}/zarr-{zarr_version}-{library}-{compressed}.zarr"
    store = get_zarr_store(fs, library, store)
    profile = f"profiles/{label}.bin"
    rm(profile)

    with memray.Tracker(profile, native_traces=True):
        z = zarr.open(store, mode="r")
        arr = z[:]
        print(arr.shape)


@cli.command()
@store_prefix_option
@compress_option
@library_option
def write(store_prefix, compress, library):
    fs = filesystem(store_prefix)
    zarr_version = find_zarr_version(library)
    compressed = "compressed" if compress else "uncompressed"
    label = f"write-{fs}-zarr-{zarr_version}-{library}-{compressed}"
    store = f"{store_prefix}/zarr-{zarr_version}-{library}-{compressed}.zarr"
    store = get_zarr_store(fs, library, store)
    profile = f"profiles/{label}.bin"
    rm(profile)

    with memray.Tracker(profile, native_traces=True):
        rng = np.random.default_rng()
        arr = rng.random((5000, 5000), dtype=np.float32)  # 100MB
        if zarr_version == "v2":
            kwargs = {}
            if not compress:
                kwargs["compressor"] = None
            z = zarr.open(
                store,
                mode="w",
                shape=arr.shape,
                dtype=arr.dtype,
                chunks=arr.shape,
                **kwargs,
            )
        else:
            kwargs = dict(config=dict(write_empty_chunks=True))
            if not compress:
                kwargs["compressors"] = None
            z = zarr.create_array(
                store=store,
                shape=arr.shape,
                dtype=arr.dtype,
                chunks=arr.shape,
                overwrite=True,
                **kwargs,
            )
        z[:] = arr


def filesystem(store_prefix):
    if store_prefix.startswith("s3://"):
        return "s3"
    return "local"


def find_zarr_version(library):
    if library == "obstore":
        return "v3"
    else:
        return "v2" if zarr.__version__ < "3" else "v3"


def get_zarr_store(fs, library, store):
    if library == "obstore":
        if fs == "local":
            local_store = obstore.store.LocalStore(prefix=store, mkdir=True)
            return zarr.storage.ObjectStore(store=local_store)
        elif fs == "s3":
            s3_store = obstore.store.S3Store.from_url(store)
            return zarr.storage.ObjectStore(store=s3_store)
        else:
            raise ValueError(f"unrecognised filesystem: {fs}")
    # for fsspec just return the store string since Zarr interprets it
    return store


def rm(filename):
    try:
        os.remove(filename)
    except OSError:
        pass


if __name__ == "__main__":
    cli()
