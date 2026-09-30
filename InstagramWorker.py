#!/usr/bin/env python3
"""Local worker for Instagram Downloader. Never writes credentials or cookies to output."""

import argparse
import json
import os
import random
import sys
import time
from pathlib import Path

PREFIX = "INSTAGRAM_DOWNLOADER_EVENT:"


def emit(event, **values):
    print(PREFIX + json.dumps({"event": event, **values}, ensure_ascii=False), flush=True)


def sleep_with_updates(seconds, reason):
    emit("status", message=f"{reason} Waiting {seconds} seconds before retrying…")
    remaining = int(seconds)
    while remaining > 0:
        step = min(10, remaining)
        time.sleep(step)
        remaining -= step
        if remaining:
            emit("status", message=f"{reason} Resuming in about {remaining} seconds…")


def import_session(args):
    try:
        import browser_cookie3
        import instaloader
    except ImportError as error:
        emit("error", message=f"Missing Python package: {error}. Click Install / Update Dependencies first.")
        return 1

    session_dir = Path(args.session_dir).expanduser()
    session_dir.mkdir(parents=True, exist_ok=True)
    session_file = session_dir / f"session-{args.username}"
    try:
        emit("status", message="Reading the signed-in Instagram cookies from Chrome…")
        cookies = browser_cookie3.chrome(domain_name=".instagram.com")
        if not any(cookie.name == "sessionid" for cookie in cookies):
            emit("error", message="No Instagram session cookie was found in Chrome. Sign in to instagram.com in Chrome and try again.")
            return 1
        loader = instaloader.Instaloader()
        loader.context._session.cookies.update(cookies)
        loader.context.username = args.username
        loader.save_session_to_file(filename=str(session_file))
        os.chmod(session_file, 0o600)
    except Exception as error:
        emit("error", message=f"Could not import the Chrome session: {error}")
        return 1

    emit("done", message="Chrome session imported locally. No password or cookie file was added to the download folder.")
    return 0


def is_rate_limit(error):
    text = str(error).lower()
    return any(term in text for term in ("429", "please wait", "rate limit", "too many requests"))


def is_auth_error(error):
    text = str(error).lower()
    return any(term in text for term in ("401", "login required", "login_required", "checkpoint", "challenge_required"))


def download(args):
    try:
        import instaloader
    except ImportError as error:
        emit("error", message=f"Missing Python package: {error}. Click Install / Update Dependencies first.")
        return 1

    session_file = Path(args.session_dir).expanduser() / f"session-{args.username}"
    if not session_file.is_file():
        emit("error", message="No saved Chrome session. Sign in to Instagram in Chrome, then click Import Chrome Session.")
        return 1

    output = Path(args.output).expanduser()
    output.mkdir(parents=True, exist_ok=True)
    loader = instaloader.Instaloader(
        download_pictures=True,
        download_videos=not args.images_only,
        download_video_thumbnails=False,
        download_geotags=False,
        download_comments=False,
        save_metadata=False,
        post_metadata_txt_pattern="",
        filename_pattern="{date_utc:%Y%m%d_%H%M%S}_{shortcode}",
        dirname_pattern=str(output),
        quiet=True,
    )

    try:
        loader.load_session_from_file(args.username, filename=str(session_file))
        emit("status", message=f"Loading @{args.target}'s post list…")
        profile = instaloader.Profile.from_username(loader.context, args.target)
        total = min(args.limit, int(profile.mediacount))
        emit("total", count=total, profile=profile.username, full_name=profile.full_name or profile.username)
        media_root = output / args.target
        media_root.mkdir(parents=True, exist_ok=True)

        processed = 0
        for post in profile.get_posts():
            if processed >= args.limit:
                break

            for attempt in range(4):
                try:
                    before = {p for p in media_root.rglob("*") if p.is_file()}
                    loader.download_post(post, target=args.target)
                    after = {p for p in media_root.rglob("*") if p.is_file()}
                    created = sorted(str(p) for p in after - before)
                    processed += 1
                    emit("post", current=processed, total=total, shortcode=post.shortcode,
                         media_count=len(created), kind="video" if post.is_video else "photo")
                    for path in created:
                        emit("file", path=path)
                    delay = random.uniform(args.delay_min, args.delay_max)
                    sleep_with_updates(delay, "Polite pause between posts.")
                    break
                except instaloader.exceptions.ConnectionException as error:
                    if is_auth_error(error):
                        emit("error", message="Instagram requires you to sign in again or approve a security check. Refresh the Chrome session and retry.")
                        return 2
                    if is_rate_limit(error):
                        if attempt >= 3:
                            emit("stopped", message="Instagram is still rate-limiting this session after three waits. The run stopped safely; downloaded files were kept.")
                            return 2
                        sleep_with_updates(60 * (2 ** attempt), "Instagram asked the app to slow down.")
                        continue
                    if attempt >= 2:
                        emit("stopped", message=f"A connection error persisted after retries: {error}. The run stopped safely; downloaded files were kept.")
                        return 2
                    sleep_with_updates(15 * (attempt + 1), "Temporary connection problem.")
                except Exception as error:
                    emit("stopped", message=f"Could not download post {post.shortcode}: {error}. The run stopped safely; downloaded files were kept.")
                    return 2

        emit("done", processed=processed, message=f"Finished. Processed {processed} post(s).")
        return 0
    except instaloader.exceptions.ProfileNotExistsException:
        emit("error", message=f"Instagram profile @{args.target} was not found.")
        return 2
    except instaloader.exceptions.LoginRequiredException:
        emit("error", message="Instagram requires an authenticated session. Import a fresh Chrome session and try again.")
        return 2
    except instaloader.exceptions.ConnectionException as error:
        emit("stopped", message=f"Could not load the profile: {error}. Wait before retrying; downloaded files were kept.")
        return 2
    except Exception as error:
        emit("stopped", message=f"Download stopped: {error}. Any downloaded files were kept.")
        return 2


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    importer = subparsers.add_parser("import-session")
    importer.add_argument("--username", required=True)
    importer.add_argument("--session-dir", required=True)
    downloader = subparsers.add_parser("download")
    downloader.add_argument("--username", required=True)
    downloader.add_argument("--target", required=True)
    downloader.add_argument("--limit", type=int, required=True)
    downloader.add_argument("--images-only", action="store_true")
    downloader.add_argument("--session-dir", required=True)
    downloader.add_argument("--output", required=True)
    downloader.add_argument("--delay-min", type=float, default=3.0)
    downloader.add_argument("--delay-max", type=float, default=8.0)
    args = parser.parse_args()
    return import_session(args) if args.command == "import-session" else download(args)


if __name__ == "__main__":
    sys.exit(main())
