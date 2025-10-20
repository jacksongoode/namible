#!/usr/bin/env python3
# coding: utf8

import subprocess
import os
import json
import sys
from PIL import Image, ImageFilter
import numpy as np


BLUR_WIDTH = 300
BLUR_RADIUS = 40.0
BAYER_MATRIX = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]])


def create_progressive_blur(image, blur_width, max_radius):
    """Applies a spatially-varying Gaussian blur with a linear falloff."""
    blurred_image = image.copy()
    strip_width = 2

    for x in range(0, blur_width, strip_width):
        radius = max_radius * (1 - (x / blur_width))
        if radius < 0.5:
            continue

        context_size = int(radius * 3)
        crop_box = (
            max(0, x - context_size),
            0,
            min(image.width, x + strip_width + context_size),
            image.height,
        )
        context_region = image.crop(crop_box)
        blurred_context = context_region.filter(ImageFilter.GaussianBlur(radius=radius))
        slice_box = (x - crop_box[0], 0, x - crop_box[0] + strip_width, image.height)
        final_strip = blurred_context.crop(slice_box)
        blurred_image.paste(final_strip, (x, 0))

    return blurred_image


def ordered_dither(image, bayer_matrix):
    """Performs ordered dithering on a grayscale image using a Bayer matrix."""
    threshold_map = (bayer_matrix + 1) / (bayer_matrix.size + 1) * 255
    img_array = np.array(image.convert("L"), dtype=np.uint8)

    height, width = img_array.shape
    rows, cols = bayer_matrix.shape
    x_coords = np.arange(width).reshape(1, width)
    y_coords = np.arange(height).reshape(height, 1)
    tiled_thresholds = threshold_map[y_coords % rows, x_coords % cols]

    dithered_array = (img_array > tiled_thresholds) * 255

    return Image.fromarray(dithered_array.astype(np.uint8)).convert("1")


def get_frame(video_id, output_filename="photo.png"):
    """Captures and styles a frame from a YouTube live stream."""
    youtube_url = f"https://www.youtube.com/watch?v={video_id}"
    try:
        print("--- Python Script Start ---")

        print("Step 1: Running yt-dlp...")
        yt_dlp_command = [
            "./yt-dlp",
            "--no-cache-dir",
            "--no-check-certificate",
            "-g",
            youtube_url,
        ]
        # A 30-second timeout is used to prevent the process from hanging indefinitely.
        result = subprocess.run(
            yt_dlp_command, check=True, capture_output=True, text=True, timeout=30
        )
        stream_url = result.stdout.strip().split("\n")[0]
        print("yt-dlp finished successfully.")

        if not stream_url.startswith("http"):
            print(f"Error: yt-dlp did not return a valid URL. Output was: {stream_url}")
            return False

        print("Step 2: Running ffmpeg...")
        temp_filename = "processed_" + output_filename
        ffmpeg_command = [
            "./ffmpeg",
            "-i",
            stream_url,
            "-vframes",
            "1",
            # The video filter rotates, scales, and crops the frame to the target dimensions.
            # Grayscale conversion and dithering are handled by the Pillow library later.
            "-vf",
            "transpose=2,scale=1236:1648:force_original_aspect_ratio=increase,crop=1236:1648",
            "-y",
            temp_filename,
        ]
        # A 30-second timeout is used to prevent the process from hanging indefinitely.
        subprocess.run(ffmpeg_command, check=True, capture_output=True, timeout=30)
        print("ffmpeg finished successfully.")

        print("Step 3: Applying blur and dither...")
        with Image.open(temp_filename) as img:
            img_rgb = img.convert("RGB")
            blurred_img = create_progressive_blur(img_rgb, BLUR_WIDTH, BLUR_RADIUS)
            img_gray = blurred_img.convert("L")
            # Dithering is temporarily disabled. Saving blurred grayscale image.
            # dithered_img = ordered_dither(img_gray, BAYER_MATRIX)
            img_gray.save(output_filename)
        os.remove(temp_filename)

        print(f"Frame styled and saved as '{output_filename}'")
        print("--- Python Script End ---")
        return True

    except subprocess.TimeoutExpired as e:
        print(f"Fatal Error: A command timed out after 30 seconds.")
        print(f"Command was: {' '.join(e.cmd)}")
        return False
    except FileNotFoundError as e:
        print(f"Error: Binary not found - {e.filename}")
        return False
    except subprocess.CalledProcessError as e:
        print(f"Error executing a binary command: {' '.join(e.cmd)}")
        print(f"Stderr: {e.stderr}")
        return False
    except Exception as e:
        print(f"An unexpected error occurred in get_frame: {e}")
        return False


def get_config():
    """Safely reads config.json and prints values for the shell script."""
    try:
        with open("config.json", "r") as f:
            config = json.load(f)
        video_id = config["youtube_video_id"]
        refresh = config["refresh_rate_seconds"]
        ssid = config["wifi_ssid"]
        psk = config["wifi_psk"]
        enable_wifi = config.get("enable_wifi", False)
        safe_mode = config.get("safe_mode", False)
        print(f"{video_id} {refresh} {ssid} {psk} {enable_wifi} {safe_mode}")
        return True
    except Exception as e:
        print(f"Fatal Error reading config.json: {e}", file=sys.stderr)
        return False


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "get-config":
        if not get_config():
            sys.exit(1)
    elif len(sys.argv) > 1 and sys.argv[1] == "get-frame":
        if not get_frame(sys.argv[2]):
            sys.exit(1)
    else:
        print(
            "Usage: python3 get_youtube_frame.py [get-config|get-frame <video_id>]",
            file=sys.stderr,
        )
        sys.exit(1)
