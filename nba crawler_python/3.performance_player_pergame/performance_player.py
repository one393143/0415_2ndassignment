from nba_api.stats.endpoints import commonteamroster, playergamelog
from nba_api.stats.static import teams
from nba_api.stats.library.http import NBAStatsHTTP
import pandas as pd
import time
import os
import json
import random
from datetime import datetime
import logging

# 設置 NBA API 的 HTTP 頭部
NBAStatsHTTP.headers = {
    'Host': 'stats.nba.com',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Accept-Encoding': 'gzip, deflate, br',
    'x-nba-stats-origin': 'stats',
    'x-nba-stats-token': 'true',
    'Connection': 'keep-alive',
    'Referer': 'https://www.nba.com/',
    'Pragma': 'no-cache',
    'Cache-Control': 'no-cache'
}

# 增加請求超時時間
NBAStatsHTTP.timeout = 45

# 設置日誌
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.FileHandler('nba_data_scraping.log'), logging.StreamHandler()]
)
logger = logging.getLogger()

# 創建存儲數據的目錄
base_dir = 'nba_data'
os.makedirs(base_dir, exist_ok=True)

# 定義要抓取的賽季和賽季類型
seasons = ['2024-25']
season_types = ['Regular Season', 'Playoffs']

# 獲取所有NBA球隊信息
nba_teams = teams.get_teams()
team_dict = {team['id']: team['full_name'] for team in nba_teams}

# 處理進度文件
progress_file = os.path.join(base_dir, 'progress.json')
if os.path.exists(progress_file):
    with open(progress_file, 'r') as f:
        progress = json.load(f)
    logger.info("已加載現有進度文件")
else:
    # 創建新的進度文件
    progress = {
        'seasons': {},
        'last_update': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    }
    # 初始化每個賽季的進度
    for season in seasons:
        progress['seasons'][season] = {
            'completed_teams': [],
            'current_team': None,
            'completed_players': [],
            'player_count': 0
        }
    with open(progress_file, 'w') as f:
        json.dump(progress, f, indent=4)
    logger.info("已創建新的進度文件")

def save_progress():
    """保存當前進度"""
    progress['last_update'] = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    with open(progress_file, 'w') as f:
        json.dump(progress, f, indent=4)

def save_season_data(season, data_df):
    """保存賽季數據到CSV文件"""
    season_file = os.path.join(base_dir, f"{season}_player_game_data.csv")
    
    if os.path.exists(season_file):
        existing_df = pd.read_csv(season_file)
        combined_df = pd.concat([existing_df, data_df], ignore_index=True)
        combined_df.to_csv(season_file, index=False)
        logger.info(f"已將 {len(data_df)} 條新數據追加到 {season_file}")
    else:
        data_df.to_csv(season_file, index=False)
        logger.info(f"已創建新文件 {season_file} 並保存 {len(data_df)} 條數據")

def get_player_game_stats(player_id, player_name, team_id, team_name, season, season_type):
    """獲取球員在指定賽季和賽季類型的每場比賽數據"""
    logger.info(f"正在抓取 {player_name} ({team_name}) 的 {season} {season_type} 數據...")
    
    max_retries = 5
    retry_delay = 0.5
    
    for attempt in range(max_retries):
        try:
            game_log = playergamelog.PlayerGameLog(
                player_id=player_id,
                season=season,
                season_type_all_star=season_type
            )
            
            df_games = game_log.get_data_frames()[0]
            
            if df_games.empty:
                logger.info(f"  {player_name} 在 {season} {season_type} 沒有比賽記錄")
                return None
            
            # 添加球員和球隊信息
            df_games['PLAYER_ID'] = player_id
            df_games['PLAYER_NAME'] = player_name
            df_games['TEAM_ID'] = team_id
            df_games['TEAM_NAME'] = team_name
            df_games['SEASON'] = season
            df_games['SEASON_TYPE'] = season_type
            
            logger.info(f"  成功抓取 {player_name} 的 {len(df_games)} 場比賽數據")
            time.sleep(random.uniform(0.1, 0.5))
            return df_games
            
        except Exception as e:
            if attempt < max_retries - 1:
                current_delay = retry_delay * (1.5 ** attempt) + random.uniform(0.1, 0.5)
                logger.warning(f"  抓取 {player_name} 數據時出錯 (嘗試 {attempt+1}/{max_retries}): {e}")
                logger.info(f"  等待 {current_delay:.2f} 秒後重試...")
                time.sleep(current_delay)
            else:
                logger.error(f"  抓取 {player_name} 數據失敗，已達最大重試次數: {e}")
                return None
    
    return None

def process_team_for_season(team_id, team_name, season, start_player_index=0):
    """處理指定球隊在特定賽季的所有球員數據"""
    logger.info(f"開始處理 {team_name} ({team_id}) 在 {season} 賽季的球員數據...")
    
    # 更新進度
    progress['seasons'][season]['current_team'] = team_id
    save_progress()
    
    try:
        # 獲取球隊陣容
        roster = commonteamroster.CommonTeamRoster(team_id=team_id, season=season)
        df_roster = roster.get_data_frames()[0]
        
        if df_roster.empty:
            logger.warning(f"  無法獲取 {team_name} 在 {season} 賽季的球員名單")
            return
        
        logger.info(f"  {team_name} 在 {season} 賽季有 {len(df_roster)} 名球員")
        
        # 用於累積球員數據
        accumulated_data = []
        player_count = 0
        
        # 處理每位球員
        for player_index, (_, player) in enumerate(df_roster.iterrows()):
            if player_index < start_player_index:
                continue
                
            player_id = player['PLAYER_ID']
            player_name = player['PLAYER']
            
            # 檢查是否已經處理過該球員
            if player_id in progress['seasons'][season]['completed_players']:
                logger.info(f"  跳過已處理的球員: {player_name}")
                continue
            
            # 處理不同賽季類型
            player_games_data = []
            for season_type in season_types:
                df_games = get_player_game_stats(
                    player_id, player_name, team_id, team_name, season, season_type
                )
                if df_games is not None and not df_games.empty:
                    player_games_data.append(df_games)
            
            # 合併該球員所有賽季類型的數據
            if player_games_data:
                player_all_games = pd.concat(player_games_data, ignore_index=True)
                accumulated_data.append(player_all_games)
                player_count += 1
                
                # 更新進度
                progress['seasons'][season]['completed_players'].append(player_id)
                progress['seasons'][season]['player_count'] += 1
                save_progress()
                
                logger.info(f"  已處理 {player_name} 的數據，當前累積 {player_count} 名球員")
                
                # 每處理5個球員，保存一次數據
                if player_count % 5 == 0 and accumulated_data:
                    combined_data = pd.concat(accumulated_data, ignore_index=True)
                    save_season_data(season, combined_data)
                    accumulated_data = []
                    logger.info(f"  已保存 {player_count} 名球員的數據")
            
            # 每處理10名球員，添加較長的休息時間
            if player_count > 0 and player_count % 10 == 0:
                rest_time = random.uniform(0.5, 1.0)
                logger.info(f"  已處理 {player_count} 名球員，休息 {rest_time:.2f} 秒...")
                time.sleep(rest_time)
        
        # 處理剩餘的球員數據
        if accumulated_data:
            combined_data = pd.concat(accumulated_data, ignore_index=True)
            save_season_data(season, combined_data)
            logger.info(f"  已保存剩餘 {len(accumulated_data)} 名球員的數據")
        
        # 完成處理
        progress['seasons'][season]['completed_teams'].append(team_id)
        progress['seasons'][season]['current_team'] = None
        save_progress()
        
        logger.info(f"完成處理 {team_name} 在 {season} 賽季的球員數據")
        
    except Exception as e:
        logger.error(f"處理 {team_name} 在 {season} 賽季時出錯: {e}")

def main():
    """主函數"""
    logger.info(f"開始抓取 {', '.join(seasons)} 賽季的NBA球員比賽數據")
    
    # 檢查是否有未完成的工作
    for season in seasons:
        current_team_id = progress['seasons'][season].get('current_team')
        if current_team_id:
            logger.info(f"從上次中斷的位置繼續: 賽季 {season}, 球隊 {team_dict.get(current_team_id, str(current_team_id))}")
            process_team_for_season(current_team_id, team_dict.get(current_team_id, "未知球隊"), season)
    
    # 處理每個賽季的所有球隊
    for season in seasons:
        logger.info(f"開始處理 {season} 賽季")
        completed_teams = progress['seasons'][season]['completed_teams']
        
        for team_id, team_name in team_dict.items():
            # 跳過已完成的球隊
            if team_id in completed_teams:
                logger.info(f"跳過已處理的球隊: {team_name} ({season})")
                continue
            
            process_team_for_season(team_id, team_name, season)
            
            # 每處理完一支球隊，添加較長的休息時間
            rest_time = random.uniform(1.0, 2.0)
            logger.info(f"完成處理一支球隊，休息 {rest_time:.2f} 秒...")
            time.sleep(rest_time)
    
    logger.info("所有賽季數據抓取完成")

if __name__ == "__main__":
    main()
