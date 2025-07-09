from nba_api.stats.endpoints import boxscoretraditionalv2, boxscoreadvancedv2, teamgamelog, leaguestandings
from nba_api.stats.static import teams
import pandas as pd
import numpy as np
import time
import os
import logging
from datetime import datetime
import concurrent.futures
import pickle
import json
from pathlib import Path
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
import traceback
import hashlib

# 定義要抓取的賽季
SEASONS = [
    '2015-16','2016-17','2017-18','2018-19','2019-20',
    '2020-21','2021-22','2022-23','2023-24','2024-25'
]

# 定義賽季類型 (移除 PlayIn)
SEASON_TYPES = ['Regular Season', 'Playoffs']

# 定義資料夾結構
OUTPUT_DIR = "output"
CACHE_DIR = "cache"
SEASONS_DIR = "seasons"
LOG_DIR = "logs"
PROGRESS_DIR = "progress"

# 設置日誌系統
def setup_logging():
    """設置日誌系統"""
    if not os.path.exists(LOG_DIR):
        os.makedirs(LOG_DIR)
    
    log_file = os.path.join(LOG_DIR, f"nba_team_games_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log")
    
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_file),
            logging.StreamHandler()
        ]
    )
    return logging.getLogger()

# 設置目錄結構
def setup_directories():
    """建立所需的資料夾結構"""
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    os.makedirs(CACHE_DIR, exist_ok=True)
    os.makedirs(SEASONS_DIR, exist_ok=True)
    os.makedirs(LOG_DIR, exist_ok=True)
    os.makedirs(PROGRESS_DIR, exist_ok=True)
    
    # 為每個賽季建立資料夾
    for season in SEASONS:
        season_dir = os.path.join(SEASONS_DIR, season)
        os.makedirs(season_dir, exist_ok=True)
        
        # 為每種賽季類型建立資料夾
        for season_type in SEASON_TYPES:
            season_type_dir = os.path.join(season_dir, season_type.replace(' ', '_'))
            os.makedirs(season_type_dir, exist_ok=True)
    
    logger.info("資料夾結構已建立")

# 設置 NBA API 請求頭和連接池
def setup_nba_api():
    """設置 NBA API 的請求頭和連接池，大幅提高請求效率"""
    # 建立自訂的 session 與重試機制
    session = requests.Session()
    retry_strategy = Retry(
        total=5,  # 增加重試次數
        backoff_factor=0.3,  # 降低退避因子，加快重試
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["GET", "POST"]
    )
    adapter = HTTPAdapter(
        max_retries=retry_strategy, 
        pool_connections=20,  # 增加連接池大小
        pool_maxsize=20,
        pool_block=False  # 不阻塞連接池
    )
    session.mount("https://", adapter)
    session.mount("http://", adapter)
    
    # 設置請求頭
    session.headers = {
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
    
    # 替換 nba_api 的默認 session
    from nba_api.stats.library.http import NBAStatsHTTP
    NBAStatsHTTP.nba_response._requests = session
    NBAStatsHTTP.headers = session.headers
    
    logger.info("NBA API 請求頭和連接池已優化設置")
    return session

# 獲取所有球隊資訊
def get_all_teams():
    """獲取所有NBA球隊資訊"""
    teams_cache_file = os.path.join(CACHE_DIR, "nba_teams.json")
    
    # 檢查是否有快取
    if os.path.exists(teams_cache_file):
        try:
            with open(teams_cache_file, 'r') as f:
                nba_teams = json.load(f)
            logger.info(f"從快取中加載了 {len(nba_teams)} 支球隊資訊")
            return nba_teams
        except Exception as e:
            logger.warning(f"讀取球隊快取時出錯: {e}")
    
    # 如果沒有快取或讀取失敗，從API獲取
    try:
        nba_teams = teams.get_teams()
        
        # 保存到快取
        with open(teams_cache_file, 'w') as f:
            json.dump(nba_teams, f)
        
        logger.info(f"從API獲取並快取了 {len(nba_teams)} 支球隊資訊")
        return nba_teams
    except Exception as e:
        logger.error(f"獲取球隊資訊時出錯: {e}")
        return []

# 計算快取鍵
def calculate_cache_key(endpoint_name, **kwargs):
    """計算API請求的快取鍵"""
    # 將參數排序並轉換為字符串
    param_str = json.dumps(kwargs, sort_keys=True)
    # 計算哈希值
    hash_obj = hashlib.md5(param_str.encode())
    return f"{endpoint_name}_{hash_obj.hexdigest()}"

# 使用快取機制獲取 API 響應
def get_cached_api_response(endpoint_func, **kwargs):
    """
    使用快取獲取 API 響應，優化版本
    
    參數:
    endpoint_func: API 端點函數
    **kwargs: API 請求參數
    
    返回:
    object: API 響應對象
    """
    # 生成快取鍵
    endpoint_name = endpoint_func.__name__
    cache_key = calculate_cache_key(endpoint_name, **kwargs)
    
    # 生成快取文件路徑
    cache_file = os.path.join(CACHE_DIR, f"{cache_key}.pkl")
    
    # 檢查快取文件是否存在
    if os.path.exists(cache_file):
        try:
            with open(cache_file, 'rb') as f:
                cached_data = pickle.load(f)
                return cached_data
        except Exception as e:
            logger.warning(f"讀取快取文件時出錯: {e}")
    
    # 如果沒有快取或讀取失敗，則進行 API 請求
    try:
        response = endpoint_func(**kwargs)
        
        # 保存到快取
        try:
            with open(cache_file, 'wb') as f:
                pickle.dump(response, f)
        except Exception as e:
            logger.warning(f"保存快取文件時出錯: {e}")
        
        return response
    except Exception as e:
        logger.error(f"API 請求 {endpoint_name} 時出錯: {e}")
        raise

# 獲取球隊的比賽日誌
def get_team_game_log(team_id, season, season_type, max_retries=3, retry_delay=0.5):
    """
    獲取球隊的比賽日誌
    
    參數:
    team_id (int): 球隊ID
    season (str): 賽季，格式為 'YYYY-YY'
    season_type (str): 賽季類型 ('Regular Season', 'Playoffs')
    max_retries (int): 最大重試次數
    retry_delay (int): 重試間隔時間（秒）
    
    返回:
    DataFrame: 包含球隊比賽日誌的DataFrame
    """
    retries = 0
    while retries < max_retries:
        try:
            # 使用快取獲取 API 響應
            game_log = get_cached_api_response(
                teamgamelog.TeamGameLog,
                team_id=team_id,
                season=season,
                season_type_all_star=season_type,
                timeout=30
            )
            
            # 獲取數據框
            df = game_log.get_data_frames()[0]
            
            if df.empty:
                logger.info(f"球隊ID {team_id} 在 {season} 賽季的 {season_type} 沒有比賽記錄")
                return pd.DataFrame()
            
            # 確保 Game_ID 欄位存在
            if 'Game_ID' not in df.columns:
                df.rename(columns={'GAME_ID': 'Game_ID'}, inplace=True)
            
            # 添加賽季和賽季類型列
            df['SEASON'] = season
            df['SEASON_TYPE'] = season_type
            
            logger.info(f"成功獲取球隊ID {team_id} 在 {season} 賽季的 {season_type} 比賽日誌，共 {len(df)} 場比賽")
            return df
            
        except Exception as e:
            retries += 1
            if retries < max_retries:
                logger.warning(f"獲取球隊ID {team_id} 的比賽日誌時出錯，第 {retries} 次重試，等待 {retry_delay} 秒...")
                time.sleep(retry_delay)
                # 每次重試增加延遲時間
                retry_delay *= 1.5
            else:
                logger.error(f"獲取球隊ID {team_id} 的比賽日誌時出錯: {e}")
                return pd.DataFrame()

# 獲取比賽詳細數據（包含傳統和進階數據）
def get_game_boxscore_complete(game_id, max_retries=3, retry_delay=0.3):
    """
    獲取比賽的完整數據（傳統 + 進階）
    
    參數:
    game_id (str): 比賽ID
    max_retries (int): 最大重試次數
    retry_delay (int): 重試間隔時間（秒）
    
    返回:
    DataFrame: 包含比賽詳細數據的DataFrame
    """
    retries = 0
    while retries < max_retries:
        try:
            # 獲取傳統統計數據
            traditional_boxscore = get_cached_api_response(
                boxscoretraditionalv2.BoxScoreTraditionalV2,
                game_id=game_id,
                timeout=30
            )
            
            # 獲取進階統計數據
            advanced_boxscore = get_cached_api_response(
                boxscoreadvancedv2.BoxScoreAdvancedV2,
                game_id=game_id,
                timeout=30
            )
            
            # 獲取球隊統計數據
            traditional_team_stats = traditional_boxscore.team_stats.get_data_frame()
            advanced_team_stats = advanced_boxscore.team_stats.get_data_frame()
            
            if traditional_team_stats.empty:
                logger.warning(f"比賽ID {game_id} 沒有團隊統計數據")
                return pd.DataFrame()
            
            # 合併傳統和進階數據
            # 先刪除進階數據中與傳統數據重複的欄位
            duplicate_columns = ['TEAM_ID', 'TEAM_NAME', 'TEAM_ABBREVIATION', 'TEAM_CITY', 'MIN', 'GAME_ID']
            advanced_columns_to_keep = [col for col in advanced_team_stats.columns if col not in duplicate_columns]
            
            # 合併數據
            team_stats = pd.merge(
                traditional_team_stats,
                advanced_team_stats[['TEAM_ID'] + advanced_columns_to_keep],
                on='TEAM_ID',
                how='left'
            )
            
            # 添加比賽ID列
            team_stats['GAME_ID'] = game_id
            team_stats['Game_ID'] = game_id
            
            return team_stats
            
        except Exception as e:
            retries += 1
            if retries < max_retries:
                logger.warning(f"獲取比賽ID {game_id} 的詳細數據時出錯，第 {retries} 次重試，等待 {retry_delay} 秒...")
                time.sleep(retry_delay)
                # 每次重試增加延遲時間
                retry_delay *= 1.5
            else:
                logger.error(f"獲取比賽ID {game_id} 的詳細數據時出錯: {e}")
                return pd.DataFrame()

# 批量處理比賽詳細數據
def process_game_batch(game_ids, season, season_type):
    """
    批量處理比賽詳細數據
    
    參數:
    game_ids (list): 比賽ID列表
    season (str): 賽季
    season_type (str): 賽季類型
    
    返回:
    DataFrame: 包含批量比賽詳細數據的DataFrame
    """
    all_team_stats = []
    
    for game_id in game_ids:
        # 獲取比賽詳細數據（包含進階數據）
        team_stats = get_game_boxscore_complete(game_id)
        
        if not team_stats.empty:
            # 添加賽季和賽季類型信息
            team_stats['SEASON'] = season
            team_stats['SEASON_TYPE'] = season_type
            all_team_stats.append(team_stats)
    
    # 合併所有比賽的團隊統計數據
    if all_team_stats:
        return pd.concat(all_team_stats, ignore_index=True)
    else:
        return pd.DataFrame()

# 並行處理多批次比賽
def process_games_parallel(all_game_ids, season, season_type, batch_size=10, max_workers=5):
    """
    並行處理多批次比賽
    
    參數:
    all_game_ids (list): 所有比賽ID列表
    season (str): 賽季
    season_type (str): 賽季類型
    batch_size (int): 每批處理的比賽數量
    max_workers (int): 並行處理的最大工作線程數
    
    返回:
    DataFrame: 包含所有批次比賽詳細數據的DataFrame
    """
    # 將比賽ID分成多個批次
    game_batches = [all_game_ids[i:i + batch_size] for i in range(0, len(all_game_ids), batch_size)]
    
    logger.info(f"將 {len(all_game_ids)} 場比賽分成 {len(game_batches)} 批進行處理，每批 {batch_size} 場")
    
    all_results = []
    
    # 並行處理每批比賽
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        # 創建任務
        future_to_batch = {
            executor.submit(process_game_batch, batch, season, season_type): i
            for i, batch in enumerate(game_batches)
        }
        
        # 獲取結果
        for future in concurrent.futures.as_completed(future_to_batch):
            batch_index = future_to_batch[future]
            try:
                result = future.result()
                if not result.empty:
                    all_results.append(result)
                    logger.info(f"完成第 {batch_index+1}/{len(game_batches)} 批比賽處理，獲取了 {len(result)} 條記錄")
                else:
                    logger.warning(f"第 {batch_index+1}/{len(game_batches)} 批比賽處理未獲取到記錄")
            except Exception as e:
                logger.error(f"處理第 {batch_index+1}/{len(game_batches)} 批比賽時出錯: {e}")
    
    # 合併所有批次的結果
    if all_results:
        return pd.concat(all_results, ignore_index=True)
    else:
        return pd.DataFrame()

# 處理單個賽季
def process_season(season, season_type, teams_list, max_workers=5, batch_size=10):
    """
    處理單個賽季的所有球隊數據，優化版本
    
    參數:
    season (str): 賽季，格式為 'YYYY-YY'
    season_type (str): 賽季類型 ('Regular Season', 'Playoffs')
    teams_list (list): 球隊信息列表
    max_workers (int): 並行處理的最大工作線程數
    batch_size (int): 每批處理的比賽數量
    
    返回:
    DataFrame: 包含該賽季所有球隊比賽數據的DataFrame
    """
    logger.info(f"開始處理 {season} 賽季的 {season_type} 數據")
    
    # 檢查進度文件
    progress_file = os.path.join(PROGRESS_DIR, f"progress_{season}_{season_type.replace(' ', '_')}.json")
    
    # 已處理的球隊和比賽
    processed_teams = set()
    processed_games = set()
    
    # 讀取進度
    if os.path.exists(progress_file):
        try:
            with open(progress_file, 'r') as f:
                progress = json.load(f)
                processed_teams = set(progress.get('processed_teams', []))
                processed_games = set(progress.get('processed_games', []))
            logger.info(f"從進度文件中恢復，已處理 {len(processed_teams)} 支球隊和 {len(processed_games)} 場比賽")
        except Exception as e:
            logger.error(f"讀取進度文件時出錯: {e}")
    
    # 收集所有球隊的比賽ID
    all_game_ids = []
    
    # 並行收集所有球隊的比賽日誌
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_team = {
            executor.submit(get_team_game_log, team['id'], season, season_type): team
            for team in teams_list if str(team['id']) not in processed_teams
        }
        
        for future in concurrent.futures.as_completed(future_to_team):
            team = future_to_team[future]
            try:
                game_log_df = future.result()
                if not game_log_df.empty:
                    # 獲取比賽ID
                    game_ids = game_log_df['Game_ID'].unique().tolist()
                    # 只添加未處理過的比賽ID
                    new_game_ids = [gid for gid in game_ids if gid not in processed_games]
                    all_game_ids.extend(new_game_ids)
                    processed_games.update(new_game_ids)
                
                # 更新已處理的球隊
                processed_teams.add(str(team['id']))
                
                # 保存進度
                progress = {
                    'processed_teams': list(processed_teams),
                    'processed_games': list(processed_games)
                }
                
                with open(progress_file, 'w') as f:
                    json.dump(progress, f)
                
            except Exception as e:
                logger.error(f"處理球隊 {team['full_name']} 的比賽日誌時出錯: {e}")
    
    # 去除重複的比賽ID
    all_game_ids = list(set(all_game_ids))
    logger.info(f"收集了 {len(all_game_ids)} 場未處理的比賽")
    
    # 如果沒有新的比賽需要處理
    if not all_game_ids:
        logger.info(f"{season} 賽季的 {season_type} 沒有新的比賽需要處理")
        
        # 檢查是否有已保存的數據
        season_type_dir = os.path.join(SEASONS_DIR, season, season_type.replace(' ', '_'))
        output_file = os.path.join(season_type_dir, f"team_game_stats_{season}_{season_type.replace(' ', '_')}.csv")
        
        if os.path.exists(output_file):
            try:
                return pd.read_csv(output_file)
            except Exception as e:
                logger.error(f"讀取已保存的數據時出錯: {e}")
                return pd.DataFrame()
        else:
            return pd.DataFrame()
    
    # 並行處理所有比賽
    combined_stats = process_games_parallel(
        all_game_ids, 
        season, 
        season_type, 
        batch_size=batch_size,
        max_workers=max_workers
    )
    
    if not combined_stats.empty:
        # 去除重複的比賽記錄（同一場比賽會在兩支球隊的記錄中出現）
        combined_stats = combined_stats.drop_duplicates(subset=['GAME_ID', 'TEAM_ID'])
        
        # 保存到文件
        season_type_dir = os.path.join(SEASONS_DIR, season, season_type.replace(' ', '_'))
        output_file = os.path.join(season_type_dir, f"team_game_stats_{season}_{season_type.replace(' ', '_')}.csv")
        
        # 檢查是否有已保存的數據
        if os.path.exists(output_file):
            try:
                existing_data = pd.read_csv(output_file)
                # 合併新舊數據
                combined_stats = pd.concat([existing_data, combined_stats], ignore_index=True)
                # 去除重複的記錄
                combined_stats = combined_stats.drop_duplicates(subset=['GAME_ID', 'TEAM_ID'])
                logger.info(f"合併了已存在的數據，總記錄數: {len(combined_stats)}")
            except Exception as e:
                logger.error(f"讀取已保存的數據時出錯: {e}")
        
        combined_stats.to_csv(output_file, index=False)
        logger.info(f"成功保存 {season} 賽季的 {season_type} 數據，共 {len(combined_stats)} 條記錄")
        
        return combined_stats
    else:
        logger.warning(f"沒有獲取到 {season} 賽季的 {season_type} 數據")
        return pd.DataFrame()

# 並行處理多個賽季
def process_multiple_seasons(seasons_to_process, season_types, teams_list, max_workers=2):
    """
    並行處理多個賽季的數據
    
    參數:
    seasons_to_process (list): 要處理的賽季列表
    season_types (list): 要處理的賽季類型列表
    teams_list (list): 球隊信息列表
    max_workers (int): 並行處理的最大工作線程數
    """
    logger.info(f"開始並行處理 {len(seasons_to_process)} 個賽季的數據，最大並行數: {max_workers}")
    
    # 創建任務列表
    tasks = []
    for season in seasons_to_process:
        for season_type in season_types:
            tasks.append((season, season_type))
    
    # 並行處理
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        # 創建任務
        future_to_task = {
            executor.submit(process_season, season, season_type, teams_list): (season, season_type)
            for season, season_type in tasks
        }
        
        # 獲取結果
        for future in concurrent.futures.as_completed(future_to_task):
            season, season_type = future_to_task[future]
            try:
                result = future.result()
                if not result.empty:
                    logger.info(f"完成 {season} 賽季的 {season_type} 數據處理，獲取了 {len(result)} 條記錄")
                else:
                    logger.warning(f"{season} 賽季的 {season_type} 數據處理未獲取到記錄")
            except Exception as e:
                logger.error(f"處理 {season} 賽季的 {season_type} 數據時出錯: {e}")

# 生成欄位說明文件
def generate_field_description():
    """生成欄位說明文件"""
    field_descriptions = """
NBA 球隊比賽數據欄位說明（續）
=========================

進階統計數據欄位（續）：
------------------
TM_TOV_PCT: 球隊失誤率 (Team Turnover Percentage)
USG_PCT: 使用率 (Usage Percentage) - 球員在場上佔用球權的比例
PACE: 進攻節奏 (Pace) - 每48分鐘的估計回合數
PIE: 球員影響力評估 (Player Impact Estimate)

數據解讀建議：
--------------
1. 效率值（Rating）越高表示球隊表現越好
2. 正負值（PLUS_MINUS）反映球隊在場上的得分優勢
3. 使用率（USG_PCT）可反映球員在球隊進攻中的重要程度

數據來源：NBA官方統計系統
數據更新時間：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
    """
    
    # 保存到文件
    description_file = os.path.join(OUTPUT_DIR, "nba_data_field_description.txt")
    with open(description_file, 'w', encoding='utf-8') as f:
        f.write(field_descriptions)
    
    logger.info(f"已生成欄位說明文件：{description_file}")
    return description_file

# 主程序
def main():
    """主程序入口"""
    try:
        # 初始化日誌系統
        global logger
        logger = setup_logging()
        
        # 設置目錄結構
        setup_directories()
        
        # 設置 NBA API
        setup_nba_api()
        
        # 獲取所有球隊
        nba_teams = get_all_teams()
        
        if not nba_teams:
            logger.error("無法獲取球隊資訊，程序終止")
            return
        
        # 並行處理多個賽季
        process_multiple_seasons(
            seasons_to_process=SEASONS,
            season_types=SEASON_TYPES,
            teams_list=nba_teams,
            max_workers=2
        )
        
        # 生成欄位說明文件
        generate_field_description()
        
        logger.info("NBA 數據抓取和處理完成")
        
    except Exception as e:
        logger.error(f"程序執行出錯: {e}")
        logger.error(traceback.format_exc())

# 程序入口
if __name__ == "__main__":
    main()

