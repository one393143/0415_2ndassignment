import requests
from bs4 import BeautifulSoup, Comment
import pandas as pd
import json
import os
import re
import time
import random
import logging
import traceback
from datetime import datetime

def setup_logging():
    """設定日誌系統"""
    log_dir = "logs"
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = os.path.join(log_dir, f"nba_br_mapping_{timestamp}.log")
    
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[logging.FileHandler(log_file), logging.StreamHandler()]
    )
    return log_file

def load_file(file_path, default=None):
    """通用檔案載入函數"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        logging.error(f"載入檔案 {file_path} 時出錯: {e}")
        return default

def save_file(data, file_path):
    """通用檔案保存函數"""
    try:
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2)
        logging.info(f"已保存資料到 {file_path}")
        return True
    except Exception as e:
        logging.error(f"保存檔案 {file_path} 時出錯: {e}")
        return False

def save_csv(data, file_path):
    """保存CSV檔案"""
    try:
        df = pd.DataFrame(data)
        df.to_csv(file_path, index=False)
        logging.info(f"已保存CSV到 {file_path}")
        return True
    except Exception as e:
        logging.error(f"保存CSV {file_path} 時出錯: {e}")
        return False

# 新增: BR與NBA球隊縮寫對照表
def get_team_abbreviation_mapping():
    """建立BR與NBA球隊縮寫對照表"""
    return {
        # BR縮寫 -> NBA縮寫
        'ATL': 'ATL',
        'BOS': 'BOS',
        'BRK': 'BKN',  # Brooklyn Nets
        'CHO': 'CHA',  # Charlotte Hornets
        'CHI': 'CHI',
        'CLE': 'CLE',
        'DAL': 'DAL',
        'DEN': 'DEN',
        'DET': 'DET',
        'GSW': 'GSW',
        'HOU': 'HOU',
        'IND': 'IND',
        'LAC': 'LAC',
        'LAL': 'LAL',
        'MEM': 'MEM',
        'MIA': 'MIA',
        'MIL': 'MIL',
        'MIN': 'MIN',
        'NOP': 'NOP',
        'NYK': 'NYK',
        'OKC': 'OKC',
        'ORL': 'ORL',
        'PHI': 'PHI',
        'PHO': 'PHX',  # Phoenix Suns
        'POR': 'POR',
        'SAC': 'SAC',
        'SAS': 'SAS',
        'TOR': 'TOR',
        'UTA': 'UTA',
        'WAS': 'WAS'
    }

def get_br_team_code(nba_team_code, team_mapping):
    """根據NBA縮寫獲取BR縮寫"""
    for br_code, nba_code in team_mapping.items():
        if nba_code == nba_team_code:
            return br_code
    return nba_team_code  # 如果找不到對應，返回原始縮寫

def get_team_players_from_br(br_team, year):
    """從Basketball Reference取得特定球隊和年份的球員資料"""
    logging.info(f"正在獲取 {br_team} 隊 {year} 賽季的球員資料...")
    
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Referer': 'https://www.basketball-reference.com/'
    }
    
    url = f"https://www.basketball-reference.com/teams/{br_team}/{year}.html"
    
    try:
        response = requests.get(url, headers=headers)
        if response.status_code != 200:
            logging.error(f"請求失敗，狀態碼: {response.status_code}, URL: {url}")
            return []
        
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # 尋找薪資表格（可能在HTML註釋中）
        salary_table = None
        for comment in soup.find_all(string=lambda text: isinstance(text, Comment)):
            if 'salaries2' in comment and 'table' in comment:
                salary_table = BeautifulSoup(comment, 'html.parser').find('table', {'id': 'salaries2'})
                if salary_table: break
        
        if not salary_table:
            salary_table = soup.find('table', {'id': 'salaries2'})
            if not salary_table:
                logging.warning(f"未找到{br_team}隊{year}賽季的薪資表格")
                return []
        
        players_data = []
        for row in salary_table.find_all('tr')[1:]:  # 跳過表頭行
            try:
                player_cell = row.find('td', {'data-stat': 'player'})
                if not player_cell or not player_cell.find('a'): continue
                
                player_link = player_cell.find('a')
                player_name = player_link.text.strip()
                player_url = player_link['href']
                
                br_id_match = re.search(r'/players/[a-z]/([a-z0-9]+)\.html', player_url)
                if not br_id_match: continue
                
                br_id = br_id_match.group(1)
                
                # 提取薪資
                salary_cell = row.find('td', {'data-stat': 'salary'})
                salary = None
                if salary_cell:
                    salary_text = re.sub(r'[$,]', '', salary_cell.text.strip())
                    try:
                        salary = int(salary_text) if salary_text else None
                    except ValueError:
                        pass
                
                players_data.append({
                    'full_name_in_br': player_name,
                    'id_in_br': br_id,
                    'br_url': f"https://www.basketball-reference.com{player_url}",
                    'salary': salary,
                    'br_team': br_team  # 保存BR的球隊縮寫
                })
            except Exception as e:
                logging.error(f"處理球員行時出錯: {e}")
        
        logging.info(f"成功獲取 {br_team} 隊 {year} 賽季的 {len(players_data)} 名球員資料")
        return players_data
    
    except Exception as e:
        logging.error(f"獲取 {br_team} 隊 {year} 賽季的球員資料時出錯: {e}")
        return []

def get_nba_id_from_br_page(br_url):
    """從Basketball Reference球員頁面獲取NBA ID"""
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Referer': 'https://www.basketball-reference.com/'
    }
    
    try:
        response = requests.get(br_url, headers=headers)
        if response.status_code != 200:
            logging.error(f"請求失敗，狀態碼: {response.status_code}, URL: {br_url}")
            return None, None
        
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # 尋找NBA.com連結
        nba_link = soup.find('a', string=lambda text: text and 'Player Front' in text)
        
        if not nba_link:
            # 嘗試另一種方式查找
            for link in soup.find_all('a'):
                if link.get('href') and 'nba.com/stats/player/' in link.get('href'):
                    nba_link = link
                    break
        
        if not nba_link:
            logging.warning(f"在{br_url}中未找到NBA.com連結")
            return None, None
        
        nba_url = nba_link.get('href')
        nba_id_match = re.search(r'/player/(\d+)', nba_url)
        
        if nba_id_match:
            nba_id = nba_id_match.group(1)
            nba_full_name = get_player_name_from_nba(nba_id)
            return nba_id, nba_full_name
        else:
            logging.warning(f"無法從{nba_url}提取NBA ID")
            return None, None
    
    except Exception as e:
        logging.error(f"處理{br_url}時出錯: {e}")
        return None, None

def get_player_name_from_nba(player_id):
    """從NBA.com獲取球員全名"""
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Referer': 'https://www.nba.com/'
    }
    
    url = f"https://www.nba.com/stats/player/{player_id}"
    
    try:
        response = requests.get(url, headers=headers)
        if response.status_code != 200:
            logging.warning(f"請求NBA.com失敗，狀態碼: {response.status_code}, URL: {url}")
            return None
        
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # 嘗試找到球員名稱
        player_name_element = soup.find('h1', {'class': 'PlayerSummary_playerNameText__K7ZgN'})
        
        if player_name_element:
            return player_name_element.text.strip()
        
        # 嘗試從標題獲取
        title_element = soup.find('title')
        if title_element and ' | ' in title_element.text:
            return title_element.text.split(' | ')[0].strip()
        
        return None
    
    except Exception as e:
        logging.error(f"從NBA.com獲取球員{player_id}名稱時出錯: {e}")
        return None

def find_nba_team_for_player(player_name, nba_players_data, season):
    """在NBA球員資料中尋找特定球員的隊伍資訊"""
    teams_info = []
    
    if not nba_players_data:
        return teams_info
    
    # 標準化球員名稱以便比較
    player_name_normalized = player_name.lower().strip()
    
    for nba_player in nba_players_data:
        nba_player_name = nba_player.get('full_name', '').lower().strip()
        
        # 如果找到匹配的球員
        if nba_player_name == player_name_normalized:
            # 檢查球員的球隊資訊
            team_abbr = nba_player.get('team_abbreviation')
            if team_abbr:
                # 檢查這個球隊是否已經添加過
                if not any(team['team'] == team_abbr for team in teams_info):
                    teams_info.append({
                        'team': team_abbr,
                        'player_id': nba_player.get('id')
                    })
    
    return teams_info

def create_player_mapping(nba_teams, years, nba_players_data, save_interval=5):
    """創建NBA和Basketball Reference球員ID對照表"""
    # 載入進度
    progress_file = "mapping_progress.json"
    progress = load_file(progress_file, {
        "completed_teams": {},
        "completed_players": {},
        "failed_players": {},
        "mappings": {}
    })
    
    # 初始化每個年份的映射
    for year in years:
        year_str = str(year)
        if year_str not in progress["mappings"]:
            progress["mappings"][year_str] = []
        if year_str not in progress["completed_teams"]:
            progress["completed_teams"][year_str] = []
    
    # 獲取球隊縮寫對照表
    team_mapping = get_team_abbreviation_mapping()
    
    try:
        for year in years:
            year_str = str(year)
            season_str = f"{year-1}-{str(year)[-2:]}"
            csv_path = f"nba_br_player_mapping_{season_str}.csv"
            
            # 將NBA縮寫轉換為BR縮寫
            br_teams = []
            for nba_team in nba_teams:
                br_team = get_br_team_code(nba_team, team_mapping)
                if br_team:
                    br_teams.append(br_team)
            
            for br_team in br_teams:
                nba_team = team_mapping.get(br_team, br_team)  # 獲取對應的NBA縮寫
                
                if nba_team in progress["completed_teams"].get(year_str, []):
                    logging.info(f"跳過已處理的隊伍: {nba_team} ({br_team}) {year}賽季")
                    continue
                
                logging.info(f"處理{nba_team}隊({br_team}) {year}賽季的數據...")
                br_players = get_team_players_from_br(br_team, year)
                
                player_count = 0
                for player in br_players:
                    player_key = f"{player['id_in_br']}_{br_team}_{year}"
                    
                    # 檢查是否已處理
                    if player_key in progress["completed_players"]:
                        logging.info(f"跳過已處理的球員: {player['full_name_in_br']} ({br_team})")
                        continue
                    
                    # 檢查是否多次失敗
                    if player_key in progress["failed_players"]:
                        retry_count = progress["failed_players"][player_key].get("retry_count", 0)
                        if retry_count >= 3:  # 最多重試3次
                            logging.warning(f"跳過多次失敗的球員: {player['full_name_in_br']} ({br_team})")
                            continue
                        logging.info(f"重試之前失敗的球員: {player['full_name_in_br']} ({br_team}), 重試次數: {retry_count + 1}")
                        progress["failed_players"][player_key]["retry_count"] = retry_count + 1
                    
                    # 添加隨機延遲
                    time.sleep(random.uniform(1, 3))
                    logging.info(f"處理球員: {player['full_name_in_br']} (BR ID: {player['id_in_br']}, 球隊: {br_team})")
                    
                    try:
                        # 從BR頁面獲取NBA ID
                        nba_id, nba_name = get_nba_id_from_br_page(player['br_url'])
                        
                        # 查找球員在NBA資料中的隊伍資訊
                        nba_teams_info = []
                        if nba_players_data:
                            if nba_id:
                                # 如果有NBA ID，優先使用ID查找
                                for nba_player in nba_players_data:
                                    if str(nba_player.get('id')) == str(nba_id):
                                        team_abbr = nba_player.get('team_abbreviation')
                                        if team_abbr and not any(info['team'] == team_abbr for info in nba_teams_info):
                                            nba_teams_info.append({
                                                'team': team_abbr,
                                                'player_id': nba_id
                                            })
                                        nba_name = nba_player.get('full_name')
                            
                            # 如果沒有找到隊伍資訊，嘗試通過名稱匹配
                            if not nba_teams_info:
                                nba_teams_info = find_nba_team_for_player(
                                    player['full_name_in_br'], 
                                    nba_players_data, 
                                    season_str
                                )
                        
                        # 如果沒有找到隊伍資訊，使用BR的隊伍資訊
                        if not nba_teams_info:
                            nba_teams_info = [{
                                'team': nba_team,  # 使用NBA縮寫
                                'player_id': nba_id
                            }]
                        
                        # 為每個隊伍創建一個映射記錄
                        for team_info in nba_teams_info:
                            mapping = {
                                'id': nba_id,
                                'full_name': nba_name if nba_name else "未知",
                                'id_in_br': player['id_in_br'],
                                'full_name_in_br': player['full_name_in_br'],
                                'team': team_info['team'],  # 使用NBA縮寫
                                'br_team': br_team,  # 保存BR縮寫以便參考
                                'season': season_str,
                                'salary': player.get('salary')
                            }
                            
                            progress["mappings"][year_str].append(mapping)
                        
                        progress["completed_players"][player_key] = True
                        if player_key in progress["failed_players"]:
                            del progress["failed_players"][player_key]
                        
                        logging.info(f"映射成功: {player['full_name_in_br']} -> {nba_name} (NBA ID: {nba_id}), 隊伍: {[info['team'] for info in nba_teams_info]}")
                        
                        player_count += 1
                        
                        # 每處理一定數量的球員，保存進度和當前年份的CSV
                        if player_count % save_interval == 0:
                            save_file(progress, progress_file)
                            save_csv(progress["mappings"][year_str], csv_path)
                            logging.info(f"已處理 {player_count} 名球員，保存進度和CSV")
                    
                    except Exception as e:
                        logging.error(f"處理球員 {player['full_name_in_br']} ({br_team}) 時出錯: {e}")
                        progress["failed_players"][player_key] = {
                            "player": player,
                            "error": str(e),
                            "retry_count": progress["failed_players"].get(player_key, {}).get("retry_count", 0) + 1
                        }
                
                # 標記該隊伍為已完成
                progress["completed_teams"].setdefault(year_str, []).append(nba_team)
                
                # 保存進度和當前年份的CSV
                save_file(progress, progress_file)
                save_csv(progress["mappings"][year_str], csv_path)
                
                logging.info(f"完成處理 {nba_team} 隊 ({br_team}) {year} 賽季的 {player_count} 名球員")
                time.sleep(random.uniform(3, 5))
            
            # 年份處理完成後，確保保存該年份的CSV
            save_csv(progress["mappings"][year_str], csv_path)
            logging.info(f"已將{season_str}賽季的球員映射保存至{csv_path}")
    
    except Exception as e:
        logging.error(f"創建球員映射時出錯: {e}")
    
    finally:
        # 保存最終進度
        save_file(progress, progress_file)
        
        # 合併所有年份的映射並保存
        all_mappings = []
        for year_mappings in progress["mappings"].values():
            all_mappings.extend(year_mappings)
        
        save_csv(all_mappings, "nba_br_player_mapping_all.csv")
        logging.info(f"已將所有賽季的球員映射保存至nba_br_player_mapping_all.csv")
    
    return all_mappings

def retry_failed_players(nba_players_data):
    """重試之前失敗的球員"""
    progress_file = "mapping_progress.json"
    progress = load_file(progress_file, {
        "completed_teams": {},
        "completed_players": {},
        "failed_players": {},
        "mappings": {}
    })
    
    team_mapping = get_team_abbreviation_mapping()
    failed_players = progress["failed_players"]
    
    if not failed_players:
        logging.info("沒有失敗的球員需要重試")
        return
    
    logging.info(f"開始重試 {len(failed_players)} 個失敗的球員")
    
    retry_count = 0
    for player_key, player_data in list(failed_players.items()):
        player = player_data.get("player")
        if not player:
            continue
        
        # 提取年份和BR隊伍
        parts = player_key.split('_')
        if len(parts) < 3:
            continue
        
        br_team = parts[1]
        year = int(parts[2])
        year_str = str(year)
        season_str = f"{year-1}-{str(year)[-2:]}"
        
        # 獲取NBA隊伍縮寫
        nba_team = team_mapping.get(br_team, br_team)
        
        logging.info(f"重試球員: {player['full_name_in_br']} (BR ID: {player['id_in_br']}, 球隊: {br_team})")
        
        try:
            time.sleep(random.uniform(1, 3))
            
            # 從BR頁面獲取NBA ID
            nba_id, nba_name = get_nba_id_from_br_page(player['br_url'])
            
            # 查找球員在NBA資料中的隊伍資訊
            nba_teams_info = []
            if nba_players_data:
                if nba_id:
                    # 如果有NBA ID，優先使用ID查找
                    for nba_player in nba_players_data:
                        if str(nba_player.get('id')) == str(nba_id):
                            team_abbr = nba_player.get('team_abbreviation')
                            if team_abbr and not any(info['team'] == team_abbr for info in nba_teams_info):
                                nba_teams_info.append({
                                    'team': team_abbr,
                                    'player_id': nba_id
                                })
                            nba_name = nba_player.get('full_name')
                
                # 如果沒有找到隊伍資訊，嘗試通過名稱匹配
                if not nba_teams_info:
                    nba_teams_info = find_nba_team_for_player(
                        player['full_name_in_br'], 
                        nba_players_data, 
                        season_str
                    )
            
            # 如果沒有找到隊伍資訊，使用BR的隊伍資訊
            if not nba_teams_info:
                nba_teams_info = [{
                    'team': nba_team,  # 使用NBA縮寫
                    'player_id': nba_id
                }]
            
            # 為每個隊伍創建一個映射記錄
            for team_info in nba_teams_info:
                mapping = {
                    'id': nba_id,
                    'full_name': nba_name if nba_name else "未知",
                    'id_in_br': player['id_in_br'],
                    'full_name_in_br': player['full_name_in_br'],
                    'team': team_info['team'],  # 使用NBA縮寫
                    'br_team': br_team,  # 保存BR縮寫以便參考
                    'season': season_str,
                    'salary': player.get('salary')
                }
                
                if year_str in progress["mappings"]:
                    progress["mappings"][year_str].append(mapping)
                else:
                    progress["mappings"][year_str] = [mapping]
            
            progress["completed_players"][player_key] = True
            del failed_players[player_key]
            
            logging.info(f"重試成功: {player['full_name_in_br']} -> {nba_name} (NBA ID: {nba_id}), 隊伍: {[info['team'] for info in nba_teams_info]}")
            
            retry_count += 1
            
            # 每重試5個球員，保存進度和CSV
            if retry_count % 5 == 0:
                save_file(progress, progress_file)
                for year in progress["mappings"]:
                    season = f"{int(year)-1}-{year[-2:]}"
                    save_csv(progress["mappings"][year], f"nba_br_player_mapping_{season}.csv")
                logging.info(f"已重試 {retry_count} 名球員，保存進度")
        
        except Exception as e:
            logging.error(f"重試球員 {player['full_name_in_br']} ({br_team}) 時出錯: {e}")
    
    # 保存最終進度和CSV
    save_file(progress, progress_file)
    for year in progress["mappings"]:
        season = f"{int(year)-1}-{year[-2:]}"
        save_csv(progress["mappings"][year], f"nba_br_player_mapping_{season}.csv")
    
    logging.info(f"完成重試 {retry_count} 名球員")

def check_missing_players(nba_players_data):
    """檢查是否有NBA球員資料中存在但映射中缺失的球員"""
    if not nba_players_data:
        logging.warning("沒有NBA球員資料可供比對")
        return
    
    progress_file = "mapping_progress.json"
    progress = load_file(progress_file, {"mappings": {}})
    
    # 獲取已映射的NBA ID
    mapped_nba_ids = set()
    for year_mappings in progress["mappings"].values():
        for mapping in year_mappings:
            if mapping.get('id'):
                mapped_nba_ids.add(str(mapping['id']))
    
    # 檢查缺失的球員
    missing_players = []
    for nba_player in nba_players_data:
        if str(nba_player.get('id')) not in mapped_nba_ids:
            missing_players.append({
                'id': nba_player.get('id'),
                'full_name': nba_player.get('full_name'),
                'team': nba_player.get('team_abbreviation'),
                'id_in_br': None,
                'full_name_in_br': None,
                'salary': None
            })
    
    if missing_players:
        logging.info(f"發現{len(missing_players)}名在NBA資料中存在但映射中缺失的球員")
        save_csv(missing_players, "missing_nba_players.csv")
    else:
        logging.info("沒有發現缺失的NBA球員")

def generate_final_report():
    """生成最終報告，包括統計信息"""
    try:
        progress_file = "mapping_progress.json"
        progress = load_file(progress_file, {"mappings": {}})
        
        # 合併所有年份的映射
        all_mappings = []
        for year_mappings in progress["mappings"].values():
            all_mappings.extend(year_mappings)
        
        # 計算統計數據
        total_mappings = len(all_mappings)
        successful_mappings = sum(1 for m in all_mappings if m.get('id') is not None)
        failed_mappings = total_mappings - successful_mappings
        success_rate = (successful_mappings / total_mappings * 100) if total_mappings > 0 else 0
        
        # 按球隊和賽季統計
        team_stats = {}
        season_stats = {}
        
        for m in all_mappings:
            team = m.get('team', 'Unknown')
            season = m.get('season', 'Unknown')
            
            if team not in team_stats:
                team_stats[team] = {'total': 0, 'successful': 0}
            team_stats[team]['total'] += 1
            if m.get('id') is not None:
                team_stats[team]['successful'] += 1
            
            if season not in season_stats:
                season_stats[season] = {'total': 0, 'successful': 0}
            season_stats[season]['total'] += 1
            if m.get('id') is not None:
                season_stats[season]['successful'] += 1
        
        # 生成報告
        report = {
            'timestamp': datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            'total_mappings': total_mappings,
            'successful_mappings': successful_mappings,
            'failed_mappings': failed_mappings,
            'success_rate': success_rate,
            'team_stats': team_stats,
            'season_stats': season_stats
        }
        
        # 保存報告
        save_file(report, 'mapping_report.json')
        
        # 輸出摘要
        logging.info(f"映射摘要: 總計 {total_mappings} 個映射, 成功 {successful_mappings} 個 ({success_rate:.2f}%), 失敗 {failed_mappings} 個")
    
    except Exception as e:
        logging.error(f"生成最終報告時出錯: {e}")

def main():
    # 設定日誌
    log_file = setup_logging()
    logging.info(f"開始執行，日誌保存在 {log_file}")
    
    # NBA球隊縮寫列表 (使用NBA官方縮寫)
    nba_teams = [
        'ATL', 'BOS', 'BKN', 'CHA', 'CHI', 'CLE', 'DAL', 'DEN', 'DET', 'GSW',
        'HOU', 'IND', 'LAC', 'LAL', 'MEM', 'MIA', 'MIL', 'MIN', 'NOP', 'NYK',
        'OKC', 'ORL', 'PHI', 'PHX', 'POR', 'SAC', 'SAS', 'TOR', 'UTA', 'WAS'
    ]
    
    # 設定要處理的賽季結束年份
    # 例如：2020 代表 2019-20 賽季
    end_years = [2020]  # 可以添加多個年份，例如 [2019, 2020, 2021]
    
    # 獲取當前腳本所在目錄
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # 依序處理每個賽季
    for end_year in end_years:
        # 計算賽季字串，例如 "2019-20"
        season_str = f"{end_year-1}-{str(end_year)[-2:]}"
        logging.info(f"開始處理 {season_str} 賽季")
        
        # 自動生成該賽季NBA球員數據文件路徑
        nba_data_file = f"nba_players_{season_str}_detailed_final.json"
        nba_data_path = os.path.join(script_dir, '..', 'read', nba_data_file)
        
        # 載入NBA球員數據
        nba_players_data = load_file(nba_data_path, [])
        
        if nba_players_data:
            logging.info(f"成功載入 {season_str} 賽季的 {len(nba_players_data)} 名NBA球員資料")
        else:
            logging.warning(f"無法載入 {season_str} 賽季的NBA球員資料，將繼續執行但無法進行本地匹配")
        
        # 創建球員映射 (只處理當前賽季)
        create_player_mapping(nba_teams, [end_year], nba_players_data, save_interval=5)
        
        # 重試該賽季失敗的球員
        retry_failed_players(nba_players_data)
        
        # 檢查該賽季缺失的球員
        check_missing_players(nba_players_data)
    
    # 生成最終報告
    generate_final_report()
    
    logging.info("程式執行完成")


if __name__ == "__main__":
    main()

