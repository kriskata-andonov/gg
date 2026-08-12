import sys
import os
if sys.stdout is None:
    sys.stdout = open(os.devnull, "w")
if sys.stderr is None:
    sys.stderr = open(os.devnull, "w")

from fastapi import FastAPI, Request, UploadFile, File, HTTPException, Response
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import os
import shutil
import sqlite3
from contextlib import contextmanager
from tinytag import TinyTag
from urllib.parse import quote

import json
import urllib.request
import urllib.parse

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

import sys

if getattr(sys, 'frozen', False):
    BASE_DIR = os.path.dirname(sys.executable)
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))

AUDIO_DIR = os.path.join(BASE_DIR, "audio_files")
if not os.path.exists(AUDIO_DIR):
    os.makedirs(AUDIO_DIR)

DB_PATH = os.path.join(BASE_DIR, "gg.db")
DEFAULT_AUDIO_DIR = AUDIO_DIR

@contextmanager
def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON;")
    try:
        yield conn
    finally:
        conn.close()

def init_db():
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS folders (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                path TEXT UNIQUE
            )
        """)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS playlists (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT UNIQUE
            )
        """)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS playlist_songs (
                playlist_id INTEGER,
                song_path TEXT,
                PRIMARY KEY (playlist_id, song_path),
                FOREIGN KEY(playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
            )
        """)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS liked_songs (
                song_path TEXT PRIMARY KEY
            )
        """)
        conn.commit()

        # Seed folders
        abs_audio_dir = os.path.abspath(DEFAULT_AUDIO_DIR)
        cursor.execute("SELECT id FROM folders WHERE path = ?", (abs_audio_dir,))
        if not cursor.fetchone():
            cursor.execute("INSERT INTO folders (path) VALUES (?)", (abs_audio_dir,))
            conn.commit()

init_db()

class FolderCreate(BaseModel):
    path: str

class LikedSongCreate(BaseModel):
    song_path: str

class PlaylistCreate(BaseModel):
    name: str

class PlaylistSongCreate(BaseModel):
    playlist_id: int
    song_path: str

class SongEdit(BaseModel):
    song_path: str
    title: str
    artist: str

@app.get("/")
def read_root():
    return {"message": "GG - Dynamic Scan Mode"}

# GET, POST, DELETE for '/api/folders'
@app.get("/api/folders")
def get_folders():
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT id, path FROM folders")
        rows = cursor.fetchall()
    return [{"id": row[0], "path": row[1]} for row in rows]

@app.post("/api/folders")
def create_folder(folder: FolderCreate):
    with get_db() as conn:
        cursor = conn.cursor()
        try:
            cursor.execute("INSERT INTO folders (path) VALUES (?)", (folder.path,))
            conn.commit()
            folder_id = cursor.lastrowid
            return {"id": folder_id, "path": folder.path}
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=400, detail="Folder already exists")

@app.delete("/api/folders")
def delete_folder(id: int = None, path: str = None):
    if id is None and path is None:
        raise HTTPException(status_code=400, detail="Must provide id or path query parameter")
    with get_db() as conn:
        cursor = conn.cursor()
        if id is not None:
            cursor.execute("DELETE FROM folders WHERE id = ?", (id,))
        else:
            cursor.execute("DELETE FROM folders WHERE path = ?", (path,))
        conn.commit()
    return {"status": "success"}


def load_folders():
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT path FROM folders")
        return [row[0] for row in cursor.fetchall()]

def load_liked_songs():
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT song_path FROM liked_songs")
        return {row[0] for row in cursor.fetchall()}

import requests
import urllib.parse
from bs4 import BeautifulSoup
import re

def get_genius_info(title, artist):
    query = title
    if artist and artist != "Unknown Artist":
        query += f" {artist}"
    
    # Clean up the query for better search results
    query = query.replace('.mp3', '')
    query = re.sub(r'\[.*?\]|\(.*?\)', '', query) # Remove [Official Video] or (Lyric Video)
    
    if " - " in query:
        # It's likely a youtube filename "Artist - Title" or "Title - Artist"
        parts = query.split(" - ")
        first = parts[0].strip()
        if len(parts) > 1:
            second = parts[1].split(',')[0].split('&')[0].split(' ft.')[0].strip()
            query = f"{first} {second}"
        else:
            query = first
            
    query = query.strip()
    
    url = f"https://genius.com/api/search/multi?q={urllib.parse.quote(query)}"
    headers = {
        'User-Agent': 'curl/7.68.0',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    }
    
    try:
        response = requests.get(url, headers=headers, timeout=5)
        if response.status_code == 200:
            data = response.json()
            for section in data['response']['sections']:
                if section['type'] == 'song' and len(section['hits']) > 0:
                    hit = section['hits'][0]['result']
                    song_url = hit['url']
                    cover_url = hit['header_image_url']
                    
                    page = requests.get(song_url, headers=headers, timeout=5)
                    soup = BeautifulSoup(page.text, 'html.parser')
                    lyrics_containers = soup.find_all('div', attrs={'data-lyrics-container': 'true'})
                    
                    lyrics = ""
                    for container in lyrics_containers:
                        lyrics += container.get_text(separator='\n') + "\n\n"
                    
                    lyrics = lyrics.strip()
                    # Remove the "X Contributors\nTitle Lyrics" prefix if present
                    lyrics = re.sub(r'^.*?Lyrics\n', '', lyrics, flags=re.IGNORECASE | re.DOTALL)
                    
                    return lyrics.strip(), cover_url
            print(f"DEBUG: No 'song' section found for {title} {artist}. Status: {response.status_code}")
        else:
            print(f"DEBUG: Genius API returned {response.status_code} for {title} {artist}")
    except Exception as e:
        print(f"Genius fetch failed for {title} {artist}: {e}")
    return "No lyrics found.", None

def _fetch_all_songs() -> list:
    songs = []
    folders = load_folders()
    liked_songs = load_liked_songs()
    
    song_metadata = {}
    try:
        with get_db() as conn:
            cursor = conn.cursor()
            cursor.execute("CREATE TABLE IF NOT EXISTS song_metadata (song_path TEXT PRIMARY KEY, title TEXT, artist TEXT)")
            cursor.execute("SELECT song_path, title, artist FROM song_metadata")
            for row in cursor.fetchall():
                song_metadata[row[0]] = {"title": row[1], "artist": row[2]}
    except Exception as e:
        print(f"Error loading song metadata: {e}")

    for folder in folders:
        if not os.path.exists(folder):
            continue
        for root, dirs, files in os.walk(folder):
            for filename in files:
                if filename.lower().endswith(".mp3"):
                    file_path = os.path.abspath(os.path.join(root, filename))
                    # Avoid duplicates if folders overlap
                    if any(s["id"] == file_path for s in songs):
                        continue
                    try:
                        tag = TinyTag.get(file_path)
                        quoted_path = quote(file_path)
                        
                        clean_filename = filename[:-4] if filename.lower().endswith(".mp3") else filename
                        
                        # Apply overrides if available
                        meta = song_metadata.get(file_path)
                        if meta:
                            title = meta["title"]
                            artist = meta["artist"]
                        else:
                            title = tag.title or clean_filename
                            artist = tag.artist or "Unknown Artist"
                        
                        songs.append({
                            "id": file_path,
                            "title": title,
                            "artist": artist,
                            "album": tag.album or "Unknown Album",
                            "audioUrl": f"http://127.0.0.1:8000/api/audio{quoted_path}",
                            "coverUrl": f"http://127.0.0.1:8000/api/cover{quoted_path}",
                            "lyrics": "Loading...",
                            "liked": file_path in liked_songs
                        })
                    except Exception as e:
                        print(f"Error parsing {file_path}: {e}")
                        quoted_path = quote(file_path)
                        clean_filename = filename[:-4] if filename.lower().endswith(".mp3") else filename
                        
                        meta = song_metadata.get(file_path)
                        if meta:
                            title = meta["title"]
                            artist = meta["artist"]
                        else:
                            title = clean_filename
                            artist = "Unknown Artist"
                        
                        songs.append({
                            "id": file_path,
                            "title": title,
                            "artist": artist,
                            "album": "Unknown Album",
                            "audioUrl": f"http://127.0.0.1:8000/api/audio{quoted_path}",
                            "coverUrl": f"http://127.0.0.1:8000/api/cover{quoted_path}",
                            "lyrics": "No lyrics found.",
                            "liked": file_path in liked_songs
                        })
    return songs

# Modify GET '/api/songs'
_songs_cache = None

def get_songs():
    global _songs_cache
    if _songs_cache is None:
        _songs_cache = _fetch_all_songs()
    return _songs_cache

@app.get("/api/songs")
def api_get_songs():
    return get_songs()

@app.get("/api/lyrics")
def get_lyrics(title: str, artist: str):
    lyrics, cover_url = get_genius_info(title, artist)
    return {"lyrics": lyrics, "coverUrl": cover_url}



@app.post("/api/scan")
def api_scan_songs():
    global _songs_cache
    _songs_cache = _fetch_all_songs()
    return {"status": "success", "count": len(_songs_cache)}

# GET '/api/audio/{path:path}'
@app.api_route("/api/audio/{path:path}", methods=["GET", "HEAD"])
def get_audio_api(path: str, request: Request):
    if not path.startswith("/"):
        path = "/" + path
    if os.path.exists(path) and os.path.isfile(path):
        return FileResponse(path, media_type="audio/mpeg")
    raise HTTPException(status_code=404, detail="File not found")

# GET '/api/cover/{path:path}'
@app.api_route("/api/cover/{path:path}", methods=["GET", "HEAD"])
def get_cover_api(path: str, request: Request):
    if not path.startswith("/"):
        path = "/" + path
    if os.path.exists(path) and os.path.isfile(path):
        try:
            tag = TinyTag.get(path, image=True)
            image_data = tag.get_image()
            if image_data:
                return Response(content=image_data, media_type="image/jpeg")
        except Exception as e:
            print(f"Error extracting cover from {path}: {e}")
    # Return a 404 so the client can fallback
    raise HTTPException(status_code=404, detail="Cover not found")

# GET, POST, DELETE for '/api/liked'
@app.get("/api/liked")
def get_liked_songs():
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT song_path FROM liked_songs")
        rows = cursor.fetchall()
    return [{"song_path": row[0]} for row in rows]

@app.post("/api/liked")
def like_song(body: LikedSongCreate):
    global _songs_cache
    with get_db() as conn:
        cursor = conn.cursor()
        try:
            cursor.execute("INSERT INTO liked_songs (song_path) VALUES (?)", (body.song_path,))
            conn.commit()
        except sqlite3.IntegrityError:
            pass
    if _songs_cache is not None:
        for s in _songs_cache:
            if s["id"] == body.song_path:
                s["liked"] = True
                break
    return {"song_path": body.song_path, "status": "liked"}

@app.delete("/api/liked")
def unlike_song(song_path: str):
    global _songs_cache
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("DELETE FROM liked_songs WHERE song_path = ?", (song_path,))
        conn.commit()
    if _songs_cache is not None:
        for s in _songs_cache:
            if s["id"] == song_path:
                s["liked"] = False
                break
    return {"status": "unliked"}

@app.post("/api/songs/edit")
def edit_song(body: SongEdit):
    global _songs_cache
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("CREATE TABLE IF NOT EXISTS song_metadata (song_path TEXT PRIMARY KEY, title TEXT, artist TEXT)")
        cursor.execute("INSERT OR REPLACE INTO song_metadata (song_path, title, artist) VALUES (?, ?, ?)", (body.song_path, body.title, body.artist))
        conn.commit()
    if _songs_cache is not None:
        for s in _songs_cache:
            if s["id"] == body.song_path:
                s["title"] = body.title
                s["artist"] = body.artist
                break
    return {"status": "success"}

@app.delete("/api/folders")
def remove_folder(folder: FolderCreate):
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("DELETE FROM folders WHERE path = ?", (folder.path,))
        conn.commit()
    return {"status": "removed"}

@app.get("/api/lyrics")
def get_lyrics(artist: str, title: str):
    try:
        url = f"https://lrclib.net/api/get?artist_name={urllib.parse.quote(artist)}&track_name={urllib.parse.quote(title)}"
        req = urllib.request.Request(url, headers={'User-Agent': 'GG-Music-App/1.0'})
        with urllib.request.urlopen(req, timeout=5) as response:
            if response.status == 200:
                data = json.loads(response.read().decode())
                lyrics = data.get("syncedLyrics") or data.get("plainLyrics")
                if lyrics:
                    return {"lyrics": lyrics}
    except Exception as e:
        print("Error fetching lyrics:", e)
    return {"lyrics": "No lyrics found."}

# GET, POST, DELETE for '/api/playlists'
@app.get("/api/playlists")
def get_playlists():
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT id, name FROM playlists")
        rows = cursor.fetchall()
    return [{"id": row[0], "name": row[1]} for row in rows]

@app.post("/api/playlists")
def create_playlist(playlist: PlaylistCreate):
    with get_db() as conn:
        cursor = conn.cursor()
        try:
            cursor.execute("INSERT INTO playlists (name) VALUES (?)", (playlist.name,))
            conn.commit()
            playlist_id = cursor.lastrowid
            return {"id": playlist_id, "name": playlist.name}
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=400, detail="Playlist already exists")

@app.delete("/api/playlists/{id}")
def delete_playlist(id: int):
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT id FROM playlists WHERE id = ?", (id,))
        if not cursor.fetchone():
            raise HTTPException(status_code=404, detail="Playlist not found")
        cursor.execute("DELETE FROM playlists WHERE id = ?", (id,))
        conn.commit()
    return {"status": "success"}

# GET, POST, DELETE for '/api/playlists/{id}/songs'
@app.get("/api/playlists/{id}/songs")
def get_playlist_songs(id: int):
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT id FROM playlists WHERE id = ?", (id,))
        if not cursor.fetchone():
            raise HTTPException(status_code=404, detail="Playlist not found")
        cursor.execute("SELECT song_path FROM playlist_songs WHERE playlist_id = ?", (id,))
        rows = cursor.fetchall()
    return [{"song_path": row[0]} for row in rows]

@app.post("/api/playlists/{id}/songs")
def add_song_to_playlist(id: int, body: PlaylistSongCreate):
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT id FROM playlists WHERE id = ?", (id,))
        if not cursor.fetchone():
            raise HTTPException(status_code=404, detail="Playlist not found")
        try:
            cursor.execute("INSERT INTO playlist_songs (playlist_id, song_path) VALUES (?, ?)", (id, body.song_path))
            conn.commit()
        except sqlite3.IntegrityError:
            pass
    return {"playlist_id": id, "song_path": body.song_path, "status": "added"}

@app.delete("/api/playlists/{id}/songs")
def remove_song_from_playlist(id: int, song_path: str):
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT id FROM playlists WHERE id = ?", (id,))
        if not cursor.fetchone():
            raise HTTPException(status_code=404, detail="Playlist not found")
        cursor.execute("DELETE FROM playlist_songs WHERE playlist_id = ? AND song_path = ?", (id, song_path))
        conn.commit()
    return {"status": "removed"}

# Keep the original upload and audio endpoint to avoid breakages
@app.post("/api/upload")
async def upload_song(file: UploadFile = File(...)):
    file_path = os.path.join(AUDIO_DIR, file.filename)
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    return {"filename": file.filename, "status": "success"}

@app.api_route("/audio/{filename}", methods=["GET", "HEAD"])
def get_audio_legacy(filename: str, request: Request):
    file_path = os.path.join(AUDIO_DIR, filename)
    if os.path.exists(file_path):
        return FileResponse(file_path, media_type="audio/mpeg")
    return {"error": "File not found"}, 404

if __name__ == "__main__":
    import uvicorn
    import multiprocessing
    multiprocessing.freeze_support()
    uvicorn.run(app, host="0.0.0.0", port=8000)
