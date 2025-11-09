#!/usr/bin/env python3
# coding: utf8

import subprocess
import os
import json
import sys
import logging
from PIL import Image, ImageFilter
import numpy as np

BLUR_WIDTH = 300
BLUR_RADIUS = 40.0
BAYER_MATRIX = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]])

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    stream=sys.stdout,
)


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
        logging.info("Starting frame capture process...")

        logging.info("Step 1: Running yt-dlp to get stream URL.")
        yt_dlp_command = [
            "./yt-dlp",
            "--no-cache-dir",
            "--no-check-certificate",
            "-g",
            youtube_url,
        ]
        result = subprocess.run(
            yt_dlp_command, check=True, capture_output=True, text=True, timeout=30
        )
        stream_url = result.stdout.strip().split("\n")[0]
        logging.info("yt-dlp finished successfully.")

        if not stream_url.startswith("http"):
            logging.error(f"yt-dlp did not return a valid URL. Output: {stream_url}")
            return False

        logging.info("Step 2: Running ffmpeg to capture a frame.")
        temp_filename = "processed_" + output_filename
        ffmpeg_command = [
            "./ffmpeg",
            "-i",
            stream_url,
            "-vframes",
            "1",
            "-vf",
            "transpose=2,scale=1236:1648:force_original_aspect_ratio=increase,crop=1236:1648",
            "-y",
            temp_filename,
        ]
        subprocess.run(ffmpeg_command, check=True, capture_output=True, timeout=30)
        logging.info("ffmpeg finished successfully.")

        logging.info("Step 3: Applying blur and dither.")
        with Image.open(temp_filename) as img:
            img_rgb = img.convert("RGB")
            blurred_img = create_progressive_blur(img_rgb, BLUR_WIDTH, BLUR_RADIUS)
            img_gray = blurred_img.convert("L")
            dithered_img = ordered_dither(img_gray, BAYER_MATRIX)
            dithered_img.save(output_filename)
        os.remove(temp_filename)

        logging.info(f"Frame styled and saved as '{output_filename}'")
        return True

    except subprocess.TimeoutExpired as e:
        logging.error(
            f"A command timed out after {e.timeout} seconds: {' '.join(e.cmd)}"
        )
        return False
    except FileNotFoundError as e:
        logging.error(f"Binary not found: {e.filename}")
        return False
    except subprocess.CalledProcessError as e:
        logging.error(f"Error executing command: {' '.join(e.cmd)}")
        logging.error(f"Stderr: {e.stderr.strip()}")
        return False
    except Exception as e:
        logging.critical(f"An unexpected error occurred: {e}")
        return False


def get_config():
    """Safely reads and parses config.json."""
    try:
        with open("config.json", "r") as f:
            config = json.load(f)
        video_id = config["youtube_video_id"]
        refresh = config["refresh_rate_seconds"]
        enable_wifi = config.get("enable_wifi", True)
        print(f"{video_id} {refresh} {enable_wifi}")
        return True
    except FileNotFoundError:
        logging.error("Fatal: config.json not found.")
        return False
    except json.JSONDecodeError:
        logging.error("Fatal: config.json is not valid JSON.")
        return False
    except KeyError as e:
        logging.error(f"Fatal: Missing key in config.json: {e}")
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
            "Usage: python3 get_namib.py [get-config|get-frame <video_id>]",
            file=sys.stderr,
        )
        sys.exit(1)
