from nba_api.stats.endpoints import leaguedashplayerstats
from nba_api.stats.endpoints import commonplayerinfo
from nba_api.stats.library.http import NBAStatsHTTP
import pandas as pd
import json
import time
import os
import logging
from datetime import datetime
import pickle
import traceback
import concurrent.futures
from functools import lru_cache
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# 定義要抓取的賽季列表
SEASONS = ['2019-20', '2020-21', '2021-22', '2022-23', '2023-24', '2024-25']

# 定義資料夾結構
OUTPUT_DIR = "output"
PROGRESS_DIR = "progress"
SEASONS_DIR = "seasons"
LOG_DIR = "logs"
CACHE_DIR = "cache"  # 新增快取目錄

# 設置日誌系統
def setup_logging():
    """設置日誌系統"""
    if not os.path.exists(LOG_DIR):
        os.makedirs(LOG_DIR)
    
    log_file = os.path.join(LOG_DIR, f"nba_player_data_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log")
    
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_file),
            logging.StreamHandler()
        ]
    )
    return logging.getLogger()

# 設置 NBA API 請求頭和連接池
def setup_nba_api():
    """設置 NBA API 的請求頭和連接池"""
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
    
    # 設置全局 requests session 與重試機制
    session = requests.Session()
    retry_strategy = Retry(
        total=3,
        backoff_factor=0.5,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["GET", "POST"]
    )
    adapter = HTTPAdapter(max_retries=retry_strategy, pool_connections=10, pool_maxsize=10)
    session.mount("https://", adapter)
    session.mount("http://", adapter)
    
    # 替換 nba_api 的默認 session
    NBAStatsHTTP.nba_response._requests = session
    
    logger.info("NBA API 請求頭和連接池已設置")

def setup_directories():
    """建立所需的資料夾結構"""
    # 建立主要資料夾
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    os.makedirs(PROGRESS_DIR, exist_ok=True)
    os.makedirs(SEASONS_DIR, exist_ok=True)
    os.makedirs(LOG_DIR, exist_ok=True)
    os.makedirs(CACHE_DIR, exist_ok=True)  # 新增快取目錄
    
    # 為每個賽季建立資料夾
    for season in SEASONS:
        season_dir = os.path.join(SEASONS_DIR, season)
        os.makedirs(season_dir, exist_ok=True)
    
    logger.info("資料夾結構已建立")

# 使用快取機制獲取 API 響應
def get_cached_api_response(endpoint, cache_key, **kwargs):
    """
    使用快取獲取 API 響應
    
    參數:
    endpoint (str): API 端點名稱
    cache_key (str): 快取鍵
    **kwargs: API 請求參數
    
    返回:
    object: API 響應對象
    """
    # 生成快取文件路徑
    cache_file = os.path.join(CACHE_DIR, f"{cache_key}.pkl")
    
    # 檢查快取文件是否存在
    if os.path.exists(cache_file):
        try:
            with open(cache_file, 'rb') as f:
                cached_data = pickle.load(f)
                logger.info(f"從快取中加載 {endpoint} 數據")
                return cached_data
        except Exception as e:
            logger.warning(f"讀取快取文件時出錯: {e}")
    
    # 如果沒有快取或讀取失敗，則進行 API 請求
    try:
        if endpoint == 'leaguedashplayerstats':
            response = leaguedashplayerstats.LeagueDashPlayerStats(**kwargs)
        elif endpoint == 'commonplayerinfo':
            response = commonplayerinfo.CommonPlayerInfo(**kwargs)
        else:
            raise ValueError(f"未知的 API 端點: {endpoint}")
        
        # 保存到快取
        try:
            with open(cache_file, 'wb') as f:
                pickle.dump(response, f)
        except Exception as e:
            logger.warning(f"保存快取文件時出錯: {e}")
        
        return response
    except Exception as e:
        logger.error(f"API 請求 {endpoint} 時出錯: {e}")
        raise

def get_players_by_season(season='2023-24', max_retries=3, retry_delay=2):
    """
    獲取特定賽季的NBA球員名單，使用快取機制
    
    參數:
    season (str): 賽季，格式為 'YYYY-YY'，例如 '2023-24'
    max_retries (int): 最大重試次數
    retry_delay (int): 重試間隔時間（秒）
    
    返回:
    DataFrame: 包含該賽季球員的基本統計數據
    """
    logger.info(f"正在獲取 {season} 賽季的球員數據...")
    
    # 生成快取鍵
    cache_key = f"leaguedashplayerstats_{season}_regular_totals"
    
    retries = 0
    while retries < max_retries:
        try:
            # 使用快取獲取 API 響應
            player_stats = get_cached_api_response(
                'leaguedashplayerstats',
                cache_key,
                season=season,
                season_type_all_star='Regular Season',
                per_mode_detailed='Totals',
                timeout=60
            )
            
            # 獲取數據框
            df = player_stats.get_data_frames()[0]
            
            # 添加賽季列
            df['SEASON'] = season
            
            logger.info(f"成功獲取 {len(df)} 名 {season} 賽季的球員數據")
            return df
            
        except Exception as e:
            retries += 1
            if "timeout" in str(e).lower() and retries < max_retries:
                logger.warning(f"獲取 {season} 賽季球員數據時超時，第 {retries} 次重試，等待 {retry_delay} 秒...")
                time.sleep(retry_delay)
                # 每次重試增加延遲時間
                retry_delay *= 1.5
            else:
                logger.error(f"獲取 {season} 賽季球員數據時出錯: {e}")
                if retries >= max_retries:
                    logger.error(f"已達最大重試次數 {max_retries}，返回空DataFrame")
                    return pd.DataFrame()

def extract_player_ids(season_stats_df):
    """
    從賽季統計數據中提取球員ID和基本資訊
    
    參數:
    season_stats_df (DataFrame): 包含賽季統計數據的DataFrame
    
    返回:
    list: 包含球員ID和基本資訊的字典列表
    """
    # 提取球員ID和姓名
    players = []
    
    if season_stats_df.empty:
        logger.warning("輸入的DataFrame為空，無法提取球員ID")
        return players
        
    try:
        # 優化：使用向量化操作而非迭代
        required_cols = ['PLAYER_ID', 'PLAYER_NAME', 'TEAM_ID', 'TEAM_ABBREVIATION', 
                         'AGE', 'GP', 'MIN', 'PTS', 'REB', 'AST', 'SEASON']
        
        # 確保所有必需列都存在
        for col in required_cols:
            if col not in season_stats_df.columns:
                season_stats_df[col] = None
        
        # 創建基本字典
        base_df = season_stats_df[required_cols].rename(columns={
            'PLAYER_ID': 'id',
            'PLAYER_NAME': 'full_name',
            'TEAM_ID': 'team_id',
            'TEAM_ABBREVIATION': 'team_abbreviation',
            'AGE': 'age',
            'GP': 'gp',
            'MIN': 'min',
            'PTS': 'pts',
            'REB': 'reb',
            'AST': 'ast',
            'SEASON': 'season'
        })
        
        # 添加可選字段
        if 'GS' in season_stats_df.columns:
            base_df['games_started'] = season_stats_df['GS']
        
        if 'PLAYER_POSITION' in season_stats_df.columns:
            base_df['player_position'] = season_stats_df['PLAYER_POSITION']
        
        # 轉換為字典列表
        players = base_df.to_dict('records')
        
        logger.info(f"已提取 {len(players)} 名球員的基本資訊")
        return players
        
    except Exception as e:
        logger.error(f"提取球員ID時出錯: {e}")
        logger.error(traceback.format_exc())
        return []

def get_player_detailed_info(player_id, max_retries=3, retry_delay=2):
    """
    獲取指定球員ID的詳細資料，使用快取機制
    
    參數:
    player_id (int): 球員ID
    max_retries (int): 最大重試次數
    retry_delay (int): 重試間隔時間（秒）
    
    返回:
    dict: 包含球員詳細資料的字典
    """
    # 生成快取鍵
    cache_key = f"commonplayerinfo_{player_id}"
    
    retries = 0
    while retries < max_retries:
        try:
            # 使用快取獲取球員詳細資料
            player_info = get_cached_api_response(
                'commonplayerinfo',
                cache_key,
                player_id=player_id,
                timeout=60
            )
            
            # 獲取常規球員資料、其他統計數據和可用年份
            common_info_df = player_info.common_player_info.get_data_frame()
            player_headline_df = player_info.player_headline_stats.get_data_frame()
            
            # 如果沒有獲取到資料，返回空字典
            if common_info_df.empty:
                logger.warning(f"球員ID {player_id} 沒有詳細資料")
                return {}
            
            # 將DataFrame轉換為字典
            player_data = common_info_df.iloc[0].to_dict()
            
            # 添加頭條統計數據
            if not player_headline_df.empty:
                player_data.update({"headline_stats": player_headline_df.iloc[0].to_dict()})
            
            logger.info(f"成功獲取球員ID {player_id} 的詳細資料")
            return player_data
            
        except Exception as e:
            retries += 1
            if "timeout" in str(e).lower() and retries < max_retries:
                logger.warning(f"獲取球員ID {player_id} 的詳細資料時超時，第 {retries} 次重試，等待 {retry_delay} 秒...")
                time.sleep(retry_delay)
                # 每次重試增加延遲時間
                retry_delay *= 1.5
            else:
                logger.error(f"獲取球員ID {player_id} 的詳細資料時出錯: {e}")
                if retries >= max_retries:
                    logger.error(f"已達最大重試次數 {max_retries}，返回空字典")
                    return {}

def load_progress(season):
    """
    加載處理進度
    
    參數:
    season (str): 賽季，用於識別進度文件
    
    返回:
    dict: 包含處理進度的字典
    """
    progress_file = os.path.join(PROGRESS_DIR, f"player_season_data_progress_{season}.pkl")
    
    if os.path.exists(progress_file):
        try:
            with open(progress_file, 'rb') as f:
                progress = pickle.load(f)
            logger.info(f"從進度文件中恢復，{season} 賽季已處理 {len(progress.get('processed_players', []))} 名球員")
            return progress
        except Exception as e:
            logger.error(f"讀取進度文件時出錯: {e}")
    
    # 如果沒有進度文件或加載失敗，創建新的進度記錄
    return {
        'processed_players': set(),  # 已處理的球員ID集合
        'failed_players': set(),     # 處理失敗的球員ID集合
        'players': []                # 已處理球員的詳細資料
    }

def save_progress(progress, season):
    """
    保存處理進度
    
    參數:
    progress (dict): 包含處理進度的字典
    season (str): 賽季，用於識別進度文件
    """
    progress_file = os.path.join(PROGRESS_DIR, f"player_season_data_progress_{season}.pkl")
    
    try:
        with open(progress_file, 'wb') as f:
            pickle.dump(progress, f)
        
        # 同時保存一個JSON版本，方便查看
        json_progress = {
            'processed_players': list(progress['processed_players']),
            'failed_players': list(progress['failed_players']),
            'processed_count': len(progress['processed_players']),
            'failed_count': len(progress['failed_players'])
        }
        
        with open(os.path.join(PROGRESS_DIR, f"player_season_data_progress_{season}.json"), 'w', encoding='utf-8') as f:
            json.dump(json_progress, f, ensure_ascii=False, indent=4)
            
        logger.info(f"{season} 賽季進度已保存: 已處理 {len(progress['processed_players'])} 名球員，失敗 {len(progress['failed_players'])} 名球員")
    except Exception as e:
        logger.error(f"保存進度文件時出錯: {e}")

# 使用並行處理獲取球員詳細資料
def process_player_batch(players_batch, max_retries=3, retry_delay=2):
    """
    並行處理一批球員的詳細資料
    
    參數:
    players_batch (list): 包含球員基本資料的列表
    max_retries (int): 最大重試次數
    retry_delay (int): 重試間隔時間（秒）
    
    返回:
    list: 包含(player_id, player_full_info)元組的列表，如果失敗則player_full_info為None
    """
    results = []
    for player in players_batch:
        player_id = player["id"]
        try:
            # 獲取詳細資料
            detailed_info = get_player_detailed_info(player_id, max_retries, retry_delay)
            
            if detailed_info:
                # 將基本資料和詳細資料合併
                player_full_info = {**player, **detailed_info}
                results.append((player_id, player_full_info))
            else:
                results.append((player_id, None))
                
            # 短暫延遲避免API限制
            time.sleep(0.2)
            
        except Exception as e:
            logger.error(f"處理球員ID {player_id} 時出錯: {e}")
            results.append((player_id, None))
    
    return results

def get_all_players_detailed_info(players, season, max_players=None, max_workers=3, batch_size=10, max_consecutive_errors=10):
    """
    獲取所有球員的詳細資料，使用並行處理
    
    參數:
    players (list): 包含球員基本資料的列表
    season (str): 賽季，用於檔案命名和進度管理
    max_players (int, optional): 最大處理球員數量，用於測試
    max_workers (int): 並行處理的最大線程數
    batch_size (int): 每批處理的球員數量
    max_consecutive_errors (int): 最大允許連續錯誤次數
    
    返回:
    list: 包含所有球員詳細資料的列表
    """
    # 過濾出特定賽季的球員
    season_players = [p for p in players if p.get('season') == season]
    
    # 確定要處理的球員數量
    players_to_process = season_players[:max_players] if max_players else season_players
    total_players = len(players_to_process)
    
    logger.info(f"開始獲取 {season} 賽季 {total_players} 名球員的詳細資料...")
    
    # 加載進度
    progress = load_progress(season)
    detailed_players = progress.get('players', [])
    processed_players = progress.get('processed_players', set())
    failed_players = progress.get('failed_players', set())
    
    # 過濾出未處理的球員
    unprocessed_players = [p for p in players_to_process if p["id"] not in processed_players]
    
    # 添加之前失敗的球員進行重試
    retry_players = [p for p in players_to_process if p["id"] in failed_players]
    unprocessed_players.extend(retry_players)
    
    # 清空失敗球員集合，因為我們將重試所有失敗的球員
    failed_players = set()
    
    logger.info(f"需要處理 {len(unprocessed_players)} 名球員（包括 {len(retry_players)} 名重試球員）")
    
    # 分批處理球員
    batches = [unprocessed_players[i:i + batch_size] for i in range(0, len(unprocessed_players), batch_size)]
    
    consecutive_errors = 0
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
            for batch_idx, batch in enumerate(batches):
                logger.info(f"處理第 {batch_idx+1}/{len(batches)} 批球員（{len(batch)} 名球員）")
                
                # 提交批次處理任務
                future = executor.submit(process_player_batch, batch)
                
                try:
                    # 獲取結果
                    results = future.result()
                    
                    # 處理結果
                    success_count = 0
                    for player_id, player_info in results:
                        if player_info:
                            detailed_players.append(player_info)
                            processed_players.add(player_id)
                            if player_id in failed_players:
                                failed_players.remove(player_id)
                            success_count += 1
                        else:
                            failed_players.add(player_id)
                    
                    # 檢查批次成功率
                    if success_count == 0 and len(batch) > 0:
                        consecutive_errors += 1
                        logger.warning(f"批次 {batch_idx+1} 完全失敗，連續失敗批次數: {consecutive_errors}")
                    else:
                        consecutive_errors = 0  # 重置連續錯誤計數
                    
                    # 檢查連續錯誤次數
                    if consecutive_errors >= max_consecutive_errors:
                        error_msg = f"檢測到 {consecutive_errors} 次連續批次錯誤，中斷處理"
                        logger.error(error_msg)
                        raise Exception(error_msg)
                    
                    # 每處理3批，保存一次進度
                    if (batch_idx + 1) % 3 == 0 or batch_idx == len(batches) - 1:
                        # 更新進度
                        progress['players'] = detailed_players
                        progress['processed_players'] = processed_players
                        progress['failed_players'] = failed_players
                        
                        # 保存進度
                        save_progress(progress, season)
                        
                        # 保存CSV檔案
                        csv_filename = os.path.join(SEASONS_DIR, season, f"nba_players_{season}_detailed_progress.csv")
                        save_to_csv(detailed_players, csv_filename)
                        
                        # 保存JSON檔案
                        json_filename = os.path.join(SEASONS_DIR, season, f"nba_players_{season}_detailed_progress.json")
                        save_to_json(detailed_players, json_filename)
                        
                        logger.info(f"進度已保存: {len(processed_players)}/{total_players}，{season} 賽季資料已保存到檔案")
                
                except Exception as e:
                    if "檢測到" in str(e) and "連續批次錯誤" in str(e):
                        # 這是我們自己拋出的連續錯誤異常，直接向上傳播
                        raise
                    
                    logger.error(f"處理第 {batch_idx+1} 批球員時出錯: {e}")
                    logger.error(traceback.format_exc())
                    consecutive_errors += 1
                    
                    # 檢查連續錯誤次數
                    if consecutive_errors >= max_consecutive_errors:
                        error_msg = f"檢測到 {consecutive_errors} 次連續批次錯誤，中斷處理"
                        logger.error(error_msg)
                        raise Exception(error_msg)
    
    except (KeyboardInterrupt, Exception) as e:
        if isinstance(e, KeyboardInterrupt):
            logger.warning(f"程序被中斷，保存 {season} 賽季當前進度...")
        else:
            logger.error(f"處理球員詳細資料時發生錯誤: {e}")
            logger.error(traceback.format_exc())
        
        # 更新進度
        progress['players'] = detailed_players
        progress['processed_players'] = processed_players
        progress['failed_players'] = failed_players
        
        # 保存進度
        save_progress(progress, season)
        
        # 保存中間結果
        csv_filename = os.path.join(SEASONS_DIR, season, f"nba_players_{season}_detailed_progress.csv")
        save_to_csv(detailed_players, csv_filename)
        
        json_filename = os.path.join(SEASONS_DIR, season, f"nba_players_{season}_detailed_progress.json")
        save_to_json(detailed_players, json_filename)
    
    return detailed_players

def save_to_csv(data, filename):
    """
    將資料保存為CSV檔案
    
    參數:
    data: 需要保存的數據
    filename (str): 輸出檔案名
    """
    try:
        if isinstance(data, list):
            # 如果是列表，轉換為DataFrame
            df = pd.DataFrame(data)
        else:
            # 如果已經是DataFrame，直接使用
            df = data
        
        # 保存為CSV
        df.to_csv(filename, index=False)
        logger.info(f"資料已保存到 {filename}")
        
        # 顯示資料結構
        logger.info(f"資料預覽：前 5 行，共 {len(df)} 行")
        
        # 顯示可用欄位
        logger.info(f"可用欄位（共 {len(df.columns)} 個）：{', '.join(df.columns)}")
        
        return df
    except Exception as e:
        logger.error(f"保存CSV檔案時出錯: {e}")
        return None

def save_to_json(data, filename):
    """
    將資料保存為JSON檔案
    
    參數:
    data: 需要保存的數據
    filename (str): 輸出檔案名
    """
    try:
        if isinstance(data, pd.DataFrame):
            # 如果是DataFrame，轉換為字典列表
            data_to_save = data.to_dict('records')
        else:
            # 否則直接使用
            data_to_save = data
        
        with open(filename, 'w', encoding='utf-8') as f:
            json.dump(data_to_save, f, ensure_ascii=False, indent=4)
        logger.info(f"資料已保存到 {filename}")
        return True
    except Exception as e:
        logger.error(f"保存JSON檔案時出錯: {e}")
        return False

def combine_all_seasons_data():
    """
    合併所有賽季的詳細球員資料到一個檔案
    """
    all_seasons_data = []
    
    # 讀取每個賽季的最終詳細資料
    for season in SEASONS:
        json_filename = os.path.join(SEASONS_DIR, season, f"nba_players_{season}_detailed_final.json")
        
        if os.path.exists(json_filename):
            try:
                with open(json_filename, 'r', encoding='utf-8') as f:
                    season_data = json.load(f)
                    all_seasons_data.extend(season_data)
                    logger.info(f"已載入 {season} 賽季的 {len(season_data)} 名球員資料")
            except Exception as e:
                logger.error(f"讀取 {season} 賽季資料時出錯: {e}")
    
    if all_seasons_data:
        # 保存合併的資料
        combined_csv = os.path.join(OUTPUT_DIR, "nba_players_all_seasons_detailed.csv")
        combined_json = os.path.join(OUTPUT_DIR, "nba_players_all_seasons_detailed.json")
        
        save_to_csv(all_seasons_data, combined_csv)
        save_to_json(all_seasons_data, combined_json)
        
        logger.info(f"已合併所有賽季的資料，總共 {len(all_seasons_data)} 筆記錄")
        
        # 分析合併資料
        df = pd.DataFrame(all_seasons_data)
        
        # 按賽季統計球員數量
        if 'season' in df.columns:
            season_counts = df['season'].value_counts().sort_index()
            logger.info("各賽季球員數量：")
            for season, count in season_counts.items():
                logger.info(f"- {season}: {count} 名球員")
        
        return True
    else:
        logger.warning("沒有找到任何賽季資料，無法合併")
        return False

def process_season(season):
    """
    處理特定賽季的球員資料
    
    參數:
    season (str): 賽季，格式如 '2023-24'
    
    返回:
    bool: 處理是否成功
    """
    logger.info(f"開始處理 {season} 賽季資料")
    
    try:
        # 獲取特定賽季的球員數據
        season_players_df = get_players_by_season(season)
        
        if season_players_df.empty:
            logger.error(f"無法獲取 {season} 賽季的球員數據")
            return False
        
        # 保存原始賽季數據
        season_dir = os.path.join(SEASONS_DIR, season)
        save_to_csv(season_players_df, os.path.join(season_dir, f"nba_players_{season}_stats.csv"))
        save_to_json(season_players_df, os.path.join(season_dir, f"nba_players_{season}_stats.json"))
        
        # 提取球員ID和基本資訊
        players_basic_info = extract_player_ids(season_players_df)
        
        if not players_basic_info:
            logger.error(f"無法提取 {season} 賽季的球員基本資訊")
            return False
        
        # 獲取所有球員的詳細資料，使用並行處理
        detailed_players = get_all_players_detailed_info(
            players_basic_info, 
            season, 
            max_workers=3,  # 並行處理的最大線程數
            batch_size=10   # 每批處理的球員數量
        )
        
        # 保存最終詳細資料
        if detailed_players:
            save_to_csv(detailed_players, os.path.join(season_dir, f"nba_players_{season}_detailed_final.csv"))
            save_to_json(detailed_players, os.path.join(season_dir, f"nba_players_{season}_detailed_final.json"))
            
            # 分析資料中的一些關鍵信息
            df = pd.DataFrame(detailed_players)
            
            # 輸出資料摘要
            logger.info(f"{season} 賽季資料摘要：")
            logger.info(f"- 總共獲取了 {len(detailed_players)} 名球員的詳細資料")
            
            # 如果有國籍信息，顯示國籍分布
            if 'COUNTRY' in df.columns:
                country_counts = df['COUNTRY'].value_counts()
                logger.info("球員國籍分布（前10項）：")
                for country, count in country_counts.head(10).items():
                    logger.info(f"- {country}: {count} 名球員")
            
            # 如果有位置信息，顯示位置分布
            if 'POSITION' in df.columns:
                position_counts = df['POSITION'].value_counts()
                logger.info("球員位置分布：")
                for position, count in position_counts.items():
                    logger.info(f"- {position}: {count} 名球員")
            
            return True
        else:
            logger.warning(f"{season} 賽季沒有獲取到球員詳細資料")
            return False
    
    except Exception as e:
        logger.error(f"處理 {season} 賽季資料時出錯: {e}")
        logger.error(traceback.format_exc())
        return False

# 並行處理所有賽季
def process_all_seasons(max_workers=2):
    """
    並行處理所有賽季的資料
    
    參數:
    max_workers (int): 並行處理的最大賽季數
    
    返回:
    tuple: (成功處理的賽季列表, 失敗處理的賽季列表)
    """
    successful_seasons = []
    failed_seasons = []
    
    logger.info(f"開始並行處理所有賽季，最大並行數: {max_workers}")
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        # 創建賽季處理任務
        future_to_season = {executor.submit(process_season, season): season for season in SEASONS}
        
        # 獲取結果
        for future in concurrent.futures.as_completed(future_to_season):
            season = future_to_season[future]
            try:
                success = future.result()
                if success:
                    successful_seasons.append(season)
                    logger.info(f"{season} 賽季資料處理成功")
                else:
                    failed_seasons.append(season)
                    logger.warning(f"{season} 賽季資料處理失敗")
            except Exception as e:
                failed_seasons.append(season)
                logger.error(f"{season} 賽季處理時發生異常: {e}")
                logger.error(traceback.format_exc())
    
    return successful_seasons, failed_seasons

def main():
    try:
        # 設置NBA API請求頭
        setup_nba_api()
        
        # 設置資料夾結構
        setup_directories()
        
        # 並行處理所有賽季
        logger.info("開始並行處理所有賽季資料...")
        successful_seasons, failed_seasons = process_all_seasons(max_workers=2)
        
        # 合併所有賽季資料
        if successful_seasons:
            combine_all_seasons_data()
        
        # 輸出處理結果摘要
        logger.info("===== 處理結果摘要 =====")
        logger.info(f"成功處理的賽季: {', '.join(successful_seasons) if successful_seasons else '無'}")
        logger.info(f"失敗處理的賽季: {', '.join(failed_seasons) if failed_seasons else '無'}")
        
        if failed_seasons:
            logger.info("請檢查日誌文件了解失敗原因，並考慮重新執行程序處理失敗的賽季")
        
        logger.info("所有賽季資料處理完成!")
        
    except Exception as e:
        logger.critical(f"處理資料時發生嚴重錯誤: {e}")
        logger.critical(traceback.format_exc())

if __name__ == "__main__":
    # 設置日誌
    logger = setup_logging()
    
    try:
        main()
    except KeyboardInterrupt:
        logger.warning("程序被使用者中斷")
    except Exception as e:
        logger.critical(f"程序執行時發生未處理的錯誤: {e}")
        logger.critical(traceback.format_exc())

        
