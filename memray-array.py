import os
import time
from pathlib import Path

import click
import memray
import numpy as np


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
    type=click.Choice(["fsspec", "obstore", "zarrista", "zarrista-obstore"]),
    help="Library to use for file IO",
)


@cli.command()
@store_prefix_option
@compress_option
@library_option
def read(store_prefix, compress, library):
    fs = filesystem(store_prefix)
    compressed = "compressed" if compress else "uncompressed"

    if library in ("zarrista", "zarrista-obstore"):
        import zarrista

        version = zarrista.__version__
        store_kind = "obstore" if library == "zarrista-obstore" else "local"
        label = f"read-{fs}-zarrista-{version}-{store_kind}-{compressed}"
        path = f"/zarrista-{version}-{store_kind}-{compressed}.zarr"
        profile = f"profiles/{label}.bin"
        rm(profile)

        if store_kind == "obstore":
            # obstore is only supported by zarrista's async API.
            import asyncio

            from zarrista import AsyncArray

            store = get_obstore_store(fs, store_prefix)

            async def read_async():
                z = await AsyncArray.open(store, path)
                return (await z[:]).to_numpy()

            with memray.Tracker(profile, native_traces=True):
                arr = asyncio.run(read_async())
                print(arr.shape)
                del arr
                time.sleep(1)
        else:
            from zarrista import Array
            from zarrista.store import FilesystemStore

            store = FilesystemStore(store_prefix)

            with memray.Tracker(profile, native_traces=True):
                z = Array.open(store, path)
                arr = z[:].to_numpy()
                print(arr.shape)
                del arr
                del z
                time.sleep(1)
    else:
        import zarr

        zarr_version = find_zarr_version()
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
    compressed = "compressed" if compress else "uncompressed"

    if library in ("zarrista", "zarrista-obstore"):
        import zarrista
        from zarrista import ArrayBuilder, ChunkGrid, DataType, FillValue, codec

        version = zarrista.__version__
        store_kind = "obstore" if library == "zarrista-obstore" else "local"
        label = f"write-{fs}-zarrista-{version}-{store_kind}-{compressed}"
        path = f"/zarrista-{version}-{store_kind}-{compressed}.zarr"
        profile = f"profiles/{label}.bin"
        rm(profile)

        def build(arr):
            grid = ChunkGrid.regular(arr.shape, chunk_shape=arr.shape)
            dtype = DataType.from_string(np.dtype(arr.dtype).name)
            fill_value = FillValue(np.zeros((), dtype=arr.dtype).tobytes())
            builder = ArrayBuilder(grid, dtype, fill_value)
            if compress:
                builder = builder.compressors([codec.zstd(3, checksum=False)])
            return builder

        if store_kind == "obstore":
            # obstore is only supported by zarrista's async API.
            import asyncio

            store = get_obstore_store(fs, store_prefix)

            async def write_async(arr):
                z = await build(arr).create_async(store, path)
                await z.store_array_subset(Ellipsis, arr)

            with memray.Tracker(profile, native_traces=True):
                rng = np.random.default_rng()
                arr = rng.random((5000, 5000), dtype=np.float32)  # 100MB
                asyncio.run(write_async(arr))
                del arr
                time.sleep(1)
        else:
            from zarrista.store import FilesystemStore

            store = FilesystemStore(store_prefix)

            with memray.Tracker(profile, native_traces=True):
                rng = np.random.default_rng()
                arr = rng.random((5000, 5000), dtype=np.float32)  # 100MB
                z = build(arr).create(store, path)
                z[:] = arr
                del arr
                del z
                time.sleep(1)
    else:
        import zarr

        zarr_version = find_zarr_version()
        label = f"write-{fs}-zarr-{zarr_version}-{library}-{compressed}"
        store = f"{store_prefix}/zarr-{zarr_version}-{library}-{compressed}.zarr"
        store = get_zarr_store(fs, library, store)
        profile = f"profiles/{label}.bin"
        rm(profile)

        with memray.Tracker(profile, native_traces=True):
            rng = np.random.default_rng()
            arr = rng.random((5000, 5000), dtype=np.float32)  # 100MB
            if zarr_version < "3":
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


def find_zarr_version():
    import zarr
    if "dev" in zarr.__version__:
        return "3-dev"
    return zarr.__version__


def get_obstore_store(fs, store_prefix):
    import obstore

    if fs == "local":
        return obstore.store.LocalStore(prefix=store_prefix, mkdir=True)
    elif fs == "s3":
        return obstore.store.S3Store.from_url(store_prefix)
    else:
        raise ValueError(f"unrecognised filesystem: {fs}")


def get_zarr_store(fs, library, store):
    if library == "obstore":
        import obstore
        import zarr
        if fs == "local":
            local_store = obstore.store.LocalStore(prefix=store, mkdir=True)
            return zarr.storage.ObjectStore(store=local_store)
        elif fs == "s3":
            s3_store = obstore.store.S3Store.from_url(store)
            return zarr.storage.ObjectStore(store=s3_store)
        else:
            raise ValueError(f"unrecognised filesystem: {fs}")
    return store


def rm(filename):
    try:
        os.remove(filename)
    except OSError:
        pass


if __name__ == "__main__":
    cli()
