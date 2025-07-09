from nba_api.stats.endpoints import leaguedashplayerstats, playercareerstats
from nba_api.stats.static import players
from nba_api.stats.library.http import NBAStatsHTTP
import pandas as pd
import time
import os
import logging
import random
import sys
import concurrent.futures
import json
from datetime import datetime

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
NBAStatsHTTP.timeout = 60

# 設置日誌
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.FileHandler('nba_data_collector.log'), logging.StreamHandler()]
)
logger = logging.getLogger()

# 設置基本參數
BASE_DIR = 'nba_data'
CACHE_DIR = os.path.join(BASE_DIR, 'cache')
SEASONS_DIR = os.path.join(BASE_DIR, 'seasons')
PLAYERS_DIR = os.path.join(BASE_DIR, 'players')
ACTIVE_PLAYERS_FILE = os.path.join(BASE_DIR, 'active_players.json')
SEASONS = [f"20{i:02d}-{(i+1):02d}" for i in range(24, 25)]  

# 創建必要的目錄
for directory in [BASE_DIR, CACHE_DIR, SEASONS_DIR, PLAYERS_DIR]:
    os.makedirs(directory, exist_ok=True)

def get_active_players():
    """獲取活躍球員列表，使用快取以避免重複請求"""
    if os.path.exists(ACTIVE_PLAYERS_FILE):
        try:
            with open(ACTIVE_PLAYERS_FILE, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"讀取活躍球員快取文件時出錯: {e}")
    
    logger.info("正在獲取所有活躍球員列表...")
    active_players = players.get_active_players()
    
    # 保存到快取
    try:
        with open(ACTIVE_PLAYERS_FILE, 'w') as f:
            json.dump(active_players, f)
    except Exception as e:
        logger.error(f"保存活躍球員列表到快取時出錯: {e}")
    
    return active_players

def get_player_stats_for_season(season, season_type='Regular Season'):
    """獲取指定賽季所有球員的統計數據"""
    cache_file = os.path.join(CACHE_DIR, f"{season}_{season_type.replace(' ', '_')}.pkl")
    
    # 檢查快取
    if os.path.exists(cache_file):
        try:
            logger.info(f"從快取中獲取 {season} {season_type} 數據...")
            return pd.read_pickle(cache_file)
        except Exception as e:
            logger.error(f"讀取快取文件時出錯: {e}")
    
    logger.info(f"正在獲取 {season} {season_type} 的所有球員數據...")
    
    try:
        # 基本數據
        basic_stats = leaguedashplayerstats.LeagueDashPlayerStats(
            season=season,
            season_type_all_star=season_type,
            per_mode_detailed='PerGame',
            measure_type_detailed_defense='Base'
        )
        basic_df = basic_stats.get_data_frames()[0]
        
        # 進階數據
        advanced_stats = leaguedashplayerstats.LeagueDashPlayerStats(
            season=season,
            season_type_all_star=season_type,
            per_mode_detailed='PerGame',
            measure_type_detailed_defense='Advanced'
        )
        advanced_df = advanced_stats.get_data_frames()[0]
        
        # 合併數據
        if not basic_df.empty and not advanced_df.empty:
            # 使用 PLAYER_ID 作為合併鍵
            merged_df = pd.merge(basic_df, advanced_df, on='PLAYER_ID', suffixes=('', '_ADV'))
            
            # 添加賽季和賽季類型信息
            merged_df['SEASON'] = season
            merged_df['SEASON_TYPE'] = season_type
            
            # 保存到快取
            try:
                merged_df.to_pickle(cache_file)
                logger.info(f"已將 {season} {season_type} 數據保存到快取")
            except Exception as e:
                logger.error(f"保存快取文件時出錯: {e}")
            
            return merged_df
        else:
            logger.warning(f"獲取 {season} {season_type} 數據失敗，返回空 DataFrame")
            return pd.DataFrame()
    
    except Exception as e:
        logger.error(f"獲取 {season} {season_type} 數據時出錯: {e}")
        return pd.DataFrame()

def get_player_career_stats(player_id, player_name):
    """獲取指定球員的職業生涯統計數據"""
    cache_file = os.path.join(CACHE_DIR, f"player_{player_id}_career.pkl")
    
    # 檢查快取
    if os.path.exists(cache_file):
        try:
            logger.info(f"從快取中獲取 {player_name} 的職業生涯數據...")
            return pd.read_pickle(cache_file)
        except Exception as e:
            logger.error(f"讀取快取文件時出錯: {e}")
    
    logger.info(f"正在獲取 {player_name} (ID: {player_id}) 的職業生涯統計數據...")
    
    try:
        # 獲取球員職業生涯統計數據
        career_stats = playercareerstats.PlayerCareerStats(player_id=player_id, per_mode36="PerGame")
        
        # 獲取常規賽數據
        regular_season = career_stats.season_totals_regular_season.get_data_frame()
        if not regular_season.empty:
            regular_season['SEASON_TYPE'] = 'Regular Season'
            logger.info(f"  成功獲取 {player_name} 的常規賽數據: {len(regular_season)} 個賽季")
        else:
            regular_season = pd.DataFrame()
            logger.warning(f"  未找到 {player_name} 的常規賽數據")
        
        # 獲取季後賽數據
        playoffs = career_stats.season_totals_post_season.get_data_frame()
        if not playoffs.empty:
            playoffs['SEASON_TYPE'] = 'Playoffs'
            logger.info(f"  成功獲取 {player_name} 的季後賽數據: {len(playoffs)} 個賽季")
        else:
            playoffs = pd.DataFrame()
            logger.warning(f"  未找到 {player_name} 的季後賽數據")
        
        # 合併常規賽和季後賽數據
        all_seasons = pd.concat([regular_season, playoffs], ignore_index=True)
        if not all_seasons.empty:
            # 添加球員名稱（如果尚未存在）
            if 'PLAYER_NAME' not in all_seasons.columns:
                all_seasons['PLAYER_NAME'] = player_name
            
            # 保存到快取
            try:
                all_seasons.to_pickle(cache_file)
                logger.info(f"已將 {player_name} 的職業生涯數據保存到快取")
            except Exception as e:
                logger.error(f"保存快取文件時出錯: {e}")
            
            return all_seasons
        else:
            logger.warning(f"  未能獲取 {player_name} 的任何賽季數據")
            return pd.DataFrame()
    
    except Exception as e:
        logger.error(f"  獲取 {player_name} 的職業生涯統計數據時出錯: {e}")
        return pd.DataFrame()

def process_season(season):
    """處理單個賽季的數據"""
    logger.info(f"開始處理 {season} 賽季數據...")
    
    # 獲取常規賽數據
    regular_season_data = get_player_stats_for_season(season, 'Regular Season')
    
    # 獲取季後賽數據
    playoffs_data = get_player_stats_for_season(season, 'Playoffs')
    
    # 合併常規賽和季後賽數據
    season_data = pd.concat([regular_season_data, playoffs_data], ignore_index=True)
    
    if not season_data.empty:
        # 創建賽季目錄
        season_dir = os.path.join(SEASONS_DIR, season)
        os.makedirs(season_dir, exist_ok=True)
        
        # 保存完整賽季數據
        season_file = os.path.join(season_dir, f"{season}_all_players.csv")
        season_data.to_csv(season_file, index=False)
        logger.info(f"已將 {season} 賽季所有球員數據保存到 {season_file}")
        
        # 按球員分別保存
        for player_id in season_data['PLAYER_ID'].unique():
            player_data = season_data[season_data['PLAYER_ID'] == player_id]
            player_name = player_data['PLAYER_NAME'].iloc[0].replace(' ', '_')
            
            # 創建球員目錄
            player_dir = os.path.join(PLAYERS_DIR, f"{player_id}_{player_name}")
            os.makedirs(player_dir, exist_ok=True)
            
            # 保存球員賽季數據
            player_season_file = os.path.join(player_dir, f"{season}.csv")
            player_data.to_csv(player_season_file, index=False)
    else:
        logger.warning(f"{season} 賽季沒有獲取到任何數據")
    
    return season

def process_player(player_info):
    """處理單個球員的數據"""
    player_id = player_info['id']
    player_name = player_info['full_name']
    
    logger.info(f"開始處理 {player_name} (ID: {player_id}) 的數據...")
    
    # 獲取球員職業生涯統計數據
    player_data = get_player_career_stats(player_id, player_name)
    
    if not player_data.empty:
        # 創建球員目錄
        player_dir = os.path.join(PLAYERS_DIR, f"{player_id}_{player_name.replace(' ', '_')}")
        os.makedirs(player_dir, exist_ok=True)
        
        # 保存球員完整職業生涯數據
        career_file = os.path.join(player_dir, "career_stats.csv")
        player_data.to_csv(career_file, index=False)
        logger.info(f"已將 {player_name} 的職業生涯數據保存到 {career_file}")
        
        # 按賽季分別保存
        for season in player_data['SEASON_ID'].unique():
            season_data = player_data[player_data['SEASON_ID'] == season]
            season_file = os.path.join(player_dir, f"{season}.csv")
            season_data.to_csv(season_file, index=False)
            logger.info(f"已將 {player_name} 的 {season} 賽季數據保存到 {season_file}")
    else:
        logger.warning(f"{player_name} 沒有獲取到任何數據")
    
    return player_name

def collect_data_by_seasons():
    """按賽季收集數據"""
    logger.info("開始按賽季收集數據...")
    
    # 使用線程池並行處理多個賽季
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        futures = {executor.submit(process_season, season): season for season in SEASONS}
        
        for future in concurrent.futures.as_completed(futures):
            season = futures[future]
            try:
                future.result()
                logger.info(f"完成處理 {season} 賽季")
            except Exception as e:
                logger.error(f"處理 {season} 賽季時出錯: {e}")

def collect_data_by_players(max_players=None):
    """按球員收集數據"""
    logger.info("開始按球員收集數據...")
    
    # 獲取活躍球員列表
    active_players = get_active_players()
    
    # 如果指定了最大球員數，則只處理部分球員
    if max_players and max_players < len(active_players):
        logger.info(f"限制處理球員數量為 {max_players}")
        active_players = active_players[:max_players]
    
    logger.info(f"共有 {len(active_players)} 名球員需要處理")
    
    # 使用線程池並行處理多個球員
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        futures = {executor.submit(process_player, player): player['full_name'] for player in active_players}
        
        for future in concurrent.futures.as_completed(futures):
            player_name = futures[future]['full_name']
            try:
                future.result()
                logger.info(f"完成處理 {player_name} 的數據")
            except Exception as e:
                logger.error(f"處理 {player_name} 的數據時出錯: {e}")

def merge_data_by_season():
    """合併每個賽季的所有球員數據"""
    logger.info("開始合併每個賽季的所有球員數據...")
    
    for season in SEASONS:
        logger.info(f"正在處理 {season} 賽季...")
        
        # 常規賽和季後賽數據文件
        season_dir = os.path.join(SEASONS_DIR, season)
        if not os.path.exists(season_dir):
            os.makedirs(season_dir, exist_ok=True)
        
        regular_season_file = os.path.join(season_dir, f"{season}_regular_season.csv")
        playoffs_file = os.path.join(season_dir, f"{season}_playoffs.csv")
        
        # 收集所有球員在該賽季的數據
        regular_season_data = []
        playoffs_data = []
        
        # 遍歷所有球員目錄
        for player_dir in os.listdir(PLAYERS_DIR):
            player_season_file = os.path.join(PLAYERS_DIR, player_dir, f"{season}.csv")
            
            if os.path.exists(player_season_file):
                try:
                    player_data = pd.read_csv(player_season_file)
                    
                    # 分離常規賽和季後賽數據
                    if 'SEASON_TYPE' in player_data.columns:
                        rs_data = player_data[player_data['SEASON_TYPE'] == 'Regular Season']
                        po_data = player_data[player_data['SEASON_TYPE'] == 'Playoffs']
                        
                        if not rs_data.empty:
                            regular_season_data.append(rs_data)
                        
                        if not po_data.empty:
                            playoffs_data.append(po_data)
                except Exception as e:
                    logger.error(f"讀取 {player_season_file} 時出錯: {e}")
        
        # 合併所有球員的常規賽數據
        if regular_season_data:
            combined_rs = pd.concat(regular_season_data, ignore_index=True)
            combined_rs.to_csv(regular_season_file, index=False)
            logger.info(f"已將 {season} 常規賽所有球員數據保存到 {regular_season_file}")
        else:
            logger.warning(f"沒有找到 {season} 常規賽數據")
        
        # 合併所有球員的季後賽數據
        if playoffs_data:
            combined_po = pd.concat(playoffs_data, ignore_index=True)
            combined_po.to_csv(playoffs_file, index=False)
            logger.info(f"已將 {season} 季後賽所有球員數據保存到 {playoffs_file}")
        else:
            logger.warning(f"沒有找到 {season} 季後賽數據")

def main():
    """主函數"""
    start_time = datetime.now()
    logger.info(f"NBA 數據收集程序開始運行，時間: {start_time}")
    
    try:
        # 選擇收集方式: 1 = 按賽季, 2 = 按球員, 3 = 兩者都執行
        collection_mode = 1
        
        if collection_mode in [1, 3]:
            collect_data_by_seasons()
        
        if collection_mode in [2, 3]:
            # 可以限制處理的球員數量，用於測試
            collect_data_by_players(max_players=50)
        
        # 合併數據
        merge_data_by_season()
        
        end_time = datetime.now()
        duration = end_time - start_time
        logger.info(f"NBA 數據收集程序完成，總耗時: {duration}")
        
    except KeyboardInterrupt:
        logger.info("程序被用戶中斷")
        sys.exit(0)
    except Exception as e:
        logger.error(f"程序執行過程中發生錯誤: {e}", exc_info=True)
        sys.exit(1)

if __name__ == "__main__":
    main()
