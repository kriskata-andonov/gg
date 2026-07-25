import os
import shutil
import pytest
from fastapi.testclient import TestClient

# Set testing DB path before importing main
import main

TEST_DB_PATH = os.path.join(main.BASE_DIR, "test_gg.db")
main.DB_PATH = TEST_DB_PATH

# Reset database for tests
if os.path.exists(TEST_DB_PATH):
    try:
        os.remove(TEST_DB_PATH)
    except Exception:
        pass
main.init_db()

client = TestClient(main.app)

@pytest.fixture(autouse=True)
def clean_db():
    # Clean tables before each test to ensure test isolation
    with main.get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("DELETE FROM playlist_songs")
        cursor.execute("DELETE FROM playlists")
        cursor.execute("DELETE FROM liked_songs")
        cursor.execute("DELETE FROM folders")
        conn.commit()
    # Re-seed the default folder
    abs_audio_dir = os.path.abspath(main.DEFAULT_AUDIO_DIR)
    with main.get_db() as conn:
        cursor = conn.cursor()
        cursor.execute("INSERT OR IGNORE INTO folders (path) VALUES (?)", (abs_audio_dir,))
        conn.commit()
    yield

def teardown_module(module):
    if os.path.exists(TEST_DB_PATH):
        try:
            os.remove(TEST_DB_PATH)
        except Exception:
            pass

def test_folders():
    # Test listing folders (should contain default)
    response = client.get("/api/folders")
    assert response.status_code == 200
    folders = response.json()
    assert len(folders) == 1
    assert folders[0]["path"] == os.path.abspath(main.DEFAULT_AUDIO_DIR)

    # Test creating folder
    new_path = os.path.abspath(os.path.join(main.BASE_DIR, "temp_test_folder"))
    response = client.post("/api/folders", json={"path": new_path})
    assert response.status_code == 200
    data = response.json()
    assert data["path"] == new_path
    assert "id" in data

    # Test duplicate folder returns 400
    response = client.post("/api/folders", json={"path": new_path})
    assert response.status_code == 400

    # Test listing folders again
    response = client.get("/api/folders")
    assert response.status_code == 200
    folders = response.json()
    assert len(folders) == 2
    paths = [f["path"] for f in folders]
    assert new_path in paths

    # Test deleting folder by path
    response = client.delete(f"/api/folders?path={new_path}")
    assert response.status_code == 200
    assert response.json() == {"status": "success"}

    # Test deleting folder by id
    response = client.post("/api/folders", json={"path": new_path})
    assert response.status_code == 200
    folder_id = response.json()["id"]
    response = client.delete(f"/api/folders?id={folder_id}")
    assert response.status_code == 200
    assert response.json() == {"status": "success"}

    # Verify it is gone
    response = client.get("/api/folders")
    folders = response.json()
    paths = [f["path"] for f in folders]
    assert new_path not in paths

def test_scan_songs():
    # Create multiple directories and files for testing scan
    dir1 = os.path.join(main.BASE_DIR, "test_scan_dir1")
    dir2 = os.path.join(main.BASE_DIR, "test_scan_dir2")
    os.makedirs(dir1, exist_ok=True)
    os.makedirs(dir2, exist_ok=True)

    song1_path = os.path.abspath(os.path.join(dir1, "song1.mp3"))
    song2_path = os.path.abspath(os.path.join(dir2, "song2.mp3"))

    with open(song1_path, "wb") as f:
        f.write(b"ID3mock") # write dummy content
    with open(song2_path, "wb") as f:
        f.write(b"ID3mock")

    try:
        # Add both directories to folders
        response = client.post("/api/folders", json={"path": os.path.abspath(dir1)})
        assert response.status_code == 200
        response = client.post("/api/folders", json={"path": os.path.abspath(dir2)})
        assert response.status_code == 200

        # Scan songs
        response = client.get("/api/songs")
        assert response.status_code == 200
        songs = response.json()
        
        song_ids = [s["id"] for s in songs]
        assert song1_path in song_ids
        assert song2_path in song_ids

        # Verify details of a song
        song1_entry = next(s for s in songs if s["id"] == song1_path)
        assert "audioUrl" in song1_entry
        assert "liked" in song1_entry
        assert song1_entry["liked"] is False

        # Test audio endpoint for the song
        audio_url_path = song1_entry["audioUrl"].split("path=")[1]
        response = client.get(f"/api/audio?path={audio_url_path}")
        assert response.status_code == 200
        # HEAD request
        response = client.request("HEAD", f"/api/audio?path={audio_url_path}")
        assert response.status_code == 200

    finally:
        # Clean up files and dirs
        if os.path.exists(song1_path):
            os.remove(song1_path)
        if os.path.exists(song2_path):
            os.remove(song2_path)
        shutil.rmtree(dir1, ignore_errors=True)
        shutil.rmtree(dir2, ignore_errors=True)

def test_playlists():
    # Create playlist
    response = client.post("/api/playlists", json={"name": "Fav Hits"})
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "Fav Hits"
    assert "id" in data
    playlist_id = data["id"]

    # Try duplicate playlist
    response = client.post("/api/playlists", json={"name": "Fav Hits"})
    assert response.status_code == 400

    # List playlists
    response = client.get("/api/playlists")
    assert response.status_code == 200
    playlists = response.json()
    assert any(p["name"] == "Fav Hits" for p in playlists)

    # Delete playlist
    response = client.delete(f"/api/playlists/{playlist_id}")
    assert response.status_code == 200

    # Verify deleted
    response = client.get("/api/playlists")
    playlists = response.json()
    assert not any(p["name"] == "Fav Hits" for p in playlists)

def test_playlist_songs():
    # Create playlist
    response = client.post("/api/playlists", json={"name": "Rock"})
    playlist_id = response.json()["id"]

    song_path = "/absolute/path/to/rock_song.mp3"

    # Add song to playlist
    response = client.post(f"/api/playlists/{playlist_id}/songs", json={"song_path": song_path})
    assert response.status_code == 200
    assert response.json()["status"] == "added"

    # List playlist songs
    response = client.get(f"/api/playlists/{playlist_id}/songs")
    assert response.status_code == 200
    songs = response.json()
    assert len(songs) == 1
    assert songs[0]["song_path"] == song_path

    # Remove song from playlist
    from urllib.parse import quote
    response = client.delete(f"/api/playlists/{playlist_id}/songs?song_path={quote(song_path)}")
    assert response.status_code == 200
    assert response.json()["status"] == "removed"

    # Verify empty playlist
    response = client.get(f"/api/playlists/{playlist_id}/songs")
    assert response.status_code == 200
    assert len(response.json()) == 0

def test_liked_songs():
    song_path = "/absolute/path/to/love_song.mp3"

    # Like a song
    response = client.post("/api/liked", json={"song_path": song_path})
    assert response.status_code == 200
    assert response.json()["status"] == "liked"

    # Check liked list
    response = client.get("/api/liked")
    assert response.status_code == 200
    liked = response.json()
    assert any(s["song_path"] == song_path for s in liked)

    # Unlike song
    from urllib.parse import quote
    response = client.delete(f"/api/liked?song_path={quote(song_path)}")
    assert response.status_code == 200
    assert response.json()["status"] == "unliked"

    # Verify not liked
    response = client.get("/api/liked")
    assert response.status_code == 200
    liked = response.json()
    assert not any(s["song_path"] == song_path for s in liked)
