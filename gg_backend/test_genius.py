import urllib.parse
import re
import requests

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
        # Just use the first part and the first artist from the second part
        first = parts[0].strip()
        second = parts[1].split(',')[0].split('&')[0].split(' ft.')[0].strip()
        query = f"{first} {second}"
        
    query = query.strip()
    
    url = f"https://genius.com/api/search/multi?q={urllib.parse.quote(query)}"
    headers = {
        'User-Agent': 'curl/7.68.0',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    }
    print("QUERY:", query)
    response = requests.get(url, headers=headers, timeout=5)
    if response.status_code == 200:
        data = response.json()
        for section in data['response']['sections']:
            if section['type'] == 'song' and len(section['hits']) > 0:
                hit = section['hits'][0]['result']
                print("FOUND:", hit['url'])
                return True
    return False

get_genius_info("Enemy - Tommee Profitt, Sam Tinnesz & Beacon Light.mp3", "Unknown Artist")
get_genius_info("Paris Paloma - labour [Official Video].mp3", "Unknown Artist")
get_genius_info("The Score, 2WEI - Down With The Wolves (Lyric Video).mp3", "Unknown Artist")
