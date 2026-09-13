#!/usr/bin/env python3
"""Exercise a bundled FFmpeg codec pair the way Firefox does.

Usage:
    LD_LIBRARY_PATH=<libdir> python3 check-decode.py <libdir> <mediadir>

Firefox 140 carries its own ffvpx decoder for VP8/VP9/AV1/Opus/Vorbis/FLAC,
but H.264 and AAC come from a SYSTEM FFmpeg that FFmpegRuntimeLinker dlopens
by soname (libavcodec.so.61 first, down to .53) and drives through
FFmpegLibWrapper's function table.  EL8 ships no FFmpeg, so build-firefox.sh
bundles a decode-only FFmpeg 7.1.x in lib/firefox/; this script proves that
pair actually decodes, not merely that the files exist.

Inputs are raw elementary streams (Annex-B H.264, ADTS AAC) in <mediadir> --
the same framing the streaming parser sees:

    h264.es  x264 main profile, 160x120, 2 s
    aac.es   AAC-LC 440 Hz sine, 2 s

Checks, in order:
  1. dlopen libavcodec.so.61 by SONAME (exactly what Firefox does), so a
     broken RPATH or missing sibling fails here.
  2. avcodec_version(): macro must be <= 61 (FFmpegRuntimeLinker's newest
     candidate -- a .62 lib is never attempted) and micro >= 100 (marks
     FFmpeg vs LibAV; FFmpegLibWrapper refuses LibAV and FFmpeg < 54.35.1).
  3. h264 + aac decoder entries resolve.
  4. Parser -> avcodec_send_packet -> avcodec_receive_frame, per codec, with
     a minimum frame count.

Exit 0 on success.  Used by build/build-firefox.sh (stage-verify) and
tests/prebuilt-binaries (installed-tree probe) so both check the same thing.
"""

import ctypes
import os
import sys

MIN_FRAMES = 10

AV_CODEC_ID_H264 = 27
AV_CODEC_ID_AAC = 86018


class AVPacket(ctypes.Structure):
    # Layout of AVPacket as of libavcodec 59-61 (the range this bundle pins).
    _fields_ = [
        ("buf", ctypes.c_void_p),
        ("pts", ctypes.c_int64),
        ("dts", ctypes.c_int64),
        ("data", ctypes.c_void_p),
        ("size", ctypes.c_int),
        ("stream_index", ctypes.c_int),
        ("flags", ctypes.c_int),
        ("side_data", ctypes.c_void_p),
        ("side_data_elems", ctypes.c_int),
        ("duration", ctypes.c_int64),
        ("pos", ctypes.c_int64),
        ("opaque", ctypes.c_void_p),
        ("opaque_ref", ctypes.c_void_p),
        ("time_base", ctypes.c_int64),
    ]


def load(libdir):
    """dlopen by SONAME from libdir, mirroring Firefox's dlopen ladder."""
    # Preload siblings in dependency order so NEEDED resolution matches what
    # the wrapper's LD_LIBRARY_PATH would provide.  Loading by absolute path
    # with RTLD_GLOBAL registers the SONAMEs the later loads look for.
    for name in ("libavutil.so.59", "libswresample.so.5"):
        path = os.path.join(libdir, name)
        if os.path.exists(path):
            ctypes.CDLL(path, mode=ctypes.RTLD_GLOBAL)
    return ctypes.CDLL("libavcodec.so.61")


def bind(avcodec, avutil):
    avcodec.avcodec_version.restype = ctypes.c_uint
    avcodec.avcodec_find_decoder_by_name.restype = ctypes.c_void_p
    avcodec.avcodec_find_decoder_by_name.argtypes = [ctypes.c_char_p]
    avcodec.avcodec_alloc_context3.restype = ctypes.c_void_p
    avcodec.avcodec_alloc_context3.argtypes = [ctypes.c_void_p]
    avcodec.avcodec_open2.restype = ctypes.c_int
    avcodec.avcodec_open2.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
    avcodec.avcodec_send_packet.restype = ctypes.c_int
    avcodec.avcodec_send_packet.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    avcodec.avcodec_receive_frame.restype = ctypes.c_int
    avcodec.avcodec_receive_frame.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    avcodec.avcodec_free_context.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
    avcodec.av_packet_alloc.restype = ctypes.c_void_p
    avcodec.av_packet_free.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
    avcodec.av_packet_unref.argtypes = [ctypes.c_void_p]
    avcodec.av_parser_init.restype = ctypes.c_void_p
    avcodec.av_parser_init.argtypes = [ctypes.c_int]
    avcodec.av_parser_parse2.restype = ctypes.c_int
    avcodec.av_parser_parse2.argtypes = [
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_void_p),
        ctypes.POINTER(ctypes.c_int),
        ctypes.c_char_p,
        ctypes.c_int,
        ctypes.c_int64,
        ctypes.c_int64,
        ctypes.c_int64,
    ]
    avcodec.av_parser_close.argtypes = [ctypes.c_void_p]
    avutil.av_frame_alloc.restype = ctypes.c_void_p
    avutil.av_frame_free.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
    # Silence libavcodec's own logging: a raw elementary stream legitimately
    # reports "no start code" at EOF (there is no end-of-stream marker), and
    # that noise obscures the real pass/fail line in both callers.
    avutil.av_log_set_level.argtypes = [ctypes.c_int]
    avutil.av_log_set_level(-8)  # AV_LOG_QUIET


def decode(avcodec, avutil, name, codec_id, path, want_frames):
    stream = open(path, "rb").read()
    codec = avcodec.avcodec_find_decoder_by_name(name.encode())
    if not codec:
        sys.exit(f"ERROR: decoder {name!r} not present in libavcodec")
    ctx = avcodec.avcodec_alloc_context3(codec)
    if avcodec.avcodec_open2(ctx, codec, None) < 0:
        sys.exit(f"ERROR: avcodec_open2({name}) failed")
    parser = avcodec.av_parser_init(codec_id)
    frame = avutil.av_frame_alloc()
    packet = avcodec.av_packet_alloc()
    got = 0
    off = 0
    while off < len(stream):
        pkt_data = ctypes.c_void_p()
        pkt_size = ctypes.c_int()
        consumed = avcodec.av_parser_parse2(
            parser,
            ctx,
            ctypes.byref(pkt_data),
            ctypes.byref(pkt_size),
            stream[off:],
            len(stream) - off,
            0,
            0,
            0,
        )
        if consumed < 0:
            break
        off += consumed
        if pkt_size.value > 0:
            avcodec.av_packet_unref(packet)
            pkt = ctypes.cast(packet, ctypes.POINTER(AVPacket)).contents
            pkt.data = pkt_data
            pkt.size = pkt_size.value
            if avcodec.avcodec_send_packet(ctx, packet) >= 0:
                while avcodec.avcodec_receive_frame(ctx, frame) >= 0:
                    got += 1
    avcodec.avcodec_send_packet(ctx, None)
    while avcodec.avcodec_receive_frame(ctx, frame) >= 0:
        got += 1
    avcodec.av_parser_close(parser)
    avcodec.avcodec_free_context(ctypes.byref(ctypes.c_void_p(ctx)))
    avutil.av_frame_free(ctypes.byref(ctypes.c_void_p(frame)))
    avcodec.av_packet_free(ctypes.byref(ctypes.c_void_p(packet)))
    if got < want_frames:
        sys.exit(f"ERROR: {name} decoded {got} frames, expected >= {want_frames}")
    print(f"  {name}: decoded {got} frames from {os.path.basename(path)}")


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: check-decode.py <libdir> <mediadir>")
    libdir, mediadir = map(os.path.abspath, sys.argv[1:3])
    try:
        avcodec = load(libdir)
    except OSError as exc:
        sys.exit(f"ERROR: cannot dlopen libavcodec.so.61 from {libdir}: {exc}")
    avutil = ctypes.CDLL(os.path.join(libdir, "libavutil.so.59"))
    bind(avcodec, avutil)

    version = avcodec.avcodec_version()
    macro = (version >> 16) & 0xFF
    micro = version & 0xFF
    print(f"  avcodec_version={version:#x} macro={macro} micro={micro}")
    if macro > 61:
        sys.exit(f"ERROR: libavcodec macro {macro} > 61 -- Firefox will not load it")
    if micro < 100:
        sys.exit(f"ERROR: libavcodec looks like LibAV (micro={micro}); Firefox refuses it")

    decode(avcodec, avutil, "h264", AV_CODEC_ID_H264, os.path.join(mediadir, "h264.es"), MIN_FRAMES)
    decode(avcodec, avutil, "aac", AV_CODEC_ID_AAC, os.path.join(mediadir, "aac.es"), MIN_FRAMES)
    print("  H.264 + AAC decode OK")


if __name__ == "__main__":
    main()
