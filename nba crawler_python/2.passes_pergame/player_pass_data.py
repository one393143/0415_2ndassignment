import os
import json
import time
import pandas as pd
import logging
from datetime import datetime
from nba_api.stats.endpoints import playerdashptpass
from nba_api.stats.endpoints import playergamelog
import argparse
import pickle
from nba_api.stats.library.http import NBAStatsHTTP
import logging
import sys
import concurrent.futures
import threading
import random
import hashlib

# 設定logging使用UTF-8編碼
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(stream=sys.stdout)  # 使用stdout而非stderr
    ]
)

# 確保stdout使用UTF-8編碼
if sys.stdout.encoding != 'utf-8':
    sys.stdout.reconfigure(encoding='utf-8')

logger = logging.getLogger(__name__)

# 全局鎖，用於控制並行請求的速率
request_lock = threading.Lock()
last_request_time = time.time()
min_request_interval = 0.6  # 最小請求間隔時間（秒）

def setup_logging(log_dir):
    """設置日誌系統"""
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)
    
    log_file = os.path.join(log_dir, f"nba_pass_data_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log")
    
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_file, encoding='utf-8'),
            logging.StreamHandler()
        ]
    )
    return logging.getLogger()

def optimize_nba_api_headers():
    """優化NBA API請求頭，使用更現代的User-Agent和更合理的參數"""
    NBAStatsHTTP.headers = {
        'Host': 'stats.nba.com',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'en-US,en;q=0.9,zh-TW;q=0.8,zh;q=0.7',
        'Accept-Encoding': 'gzip, deflate, br',
        'x-nba-stats-origin': 'stats',
        'x-nba-stats-token': 'true',
        'Connection': 'keep-alive',
        'Referer': 'https://www.nba.com/stats/',
        'sec-ch-ua': '"Not_A Brand";v="8", "Chromium";v="120"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
        'Sec-Fetch-Dest': 'empty',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'same-origin',
        'Pragma': 'no-cache',
        'Cache-Control': 'no-cache'
    }

def rate_limited_request(func, *args, **kwargs):
    """控制請求速率的裝飾器函數"""
    global last_request_time
    
    with request_lock:
        # 計算自上次請求以來的時間
        current_time = time.time()
        elapsed = current_time - last_request_time
        
        # 如果間隔時間不夠，則等待
        if elapsed < min_request_interval:
            time.sleep(min_request_interval - elapsed)
        
        # 更新上次請求時間
        last_request_time = time.time()
    
    # 執行實際請求
    return func(*args, **kwargs)

def smart_retry(func, *args, max_retries=5, base_delay=1, **kwargs):
    """智能重試機制，使用指數退避策略"""
    last_exception = None
    
    for attempt in range(max_retries):
        try:
            return func(*args, **kwargs)
        except Exception as e:
            last_exception = e
            
            # 計算延遲時間 (指數退避)
            delay = base_delay * (2 ** attempt) + random.uniform(0, 1)
            
            # 根據錯誤類型調整策略
            if "timeout" in str(e).lower():
                logger.warning(f"請求超時，第 {attempt+1}/{max_retries} 次重試，等待 {delay:.2f} 秒...")
            elif "too many requests" in str(e).lower() or "429" in str(e):
                # 遇到速率限制，增加延遲
                delay *= 2
                logger.warning(f"遇到速率限制，第 {attempt+1}/{max_retries} 次重試，等待 {delay:.2f} 秒...")
            else:
                logger.warning(f"請求失敗: {e}，第 {attempt+1}/{max_retries} 次重試，等待 {delay:.2f} 秒...")
            
            time.sleep(delay)
    
    # 所有重試都失敗
    logger.error(f"達到最大重試次數 {max_retries}，最後錯誤: {last_exception}")
    raise last_exception

def load_player_list(json_file, season):
    """從JSON文件加載球員列表"""
    try:
        with open(json_file, 'r', encoding='utf-8') as f:
            players = json.load(f)
        
        # 過濾出在指定賽季有比賽記錄的球員
        filtered_players = [p for p in players if p.get('season') == season]
        
        logger.info(f"從 {json_file} 加載了 {len(filtered_players)} 名球員 (賽季 {season})")
        return filtered_players
    except Exception as e:
        logger.error(f"加載球員列表時出錯: {e}")
        return []

def load_progress(progress_file):
    """加載處理進度"""
    if os.path.exists(progress_file):
        try:
            with open(progress_file, 'rb') as f:
                progress = pickle.load(f)
            logger.info(f"加載進度: 已處理 {len(progress['processed_players'])} 名球員")
            return progress
        except Exception as e:
            logger.error(f"加載進度文件時出錯: {e}")
    
    # 如果沒有進度文件或加載失敗，創建新的進度記錄
    return {
        'processed_players': set(),
        'failed_players': set(),
        'last_processed_index': -1
    }

def save_progress(progress, progress_file):
    """保存處理進度"""
    try:
        with open(progress_file, 'wb') as f:
            pickle.dump(progress, f)
        logger.info(f"進度已保存: 已處理 {len(progress['processed_players'])} 名球員")
    except Exception as e:
        logger.error(f"保存進度時出錯: {e}")

def get_cache_key(player_id, game_date, season_year, season_type):
    """生成緩存鍵"""
    key = f"{player_id}_{game_date}_{season_year}_{season_type}"
    return hashlib.md5(key.encode()).hexdigest()

def get_player_games_in_season(player_id, season_year, season_type="Regular Season"):
    """獲取指定球員在特定賽季的所有比賽記錄"""
    try:
        # 將年份格式轉換為NBA API需要的格式 (例如: 2023-24)
        season = f"{season_year}-{str(season_year + 1)[-2:]}"
        
        # 使用速率限制請求
        def fetch_game_log():
            game_log = playergamelog.PlayerGameLog(
                player_id=player_id,
                season=season,
                season_type_all_star=season_type,
                timeout=45
            )
            return game_log.get_data_frames()[0]
        
        # 使用速率限制和智能重試
        games_df = rate_limited_request(
            smart_retry, 
            fetch_game_log, 
            max_retries=3, 
            base_delay=2
        )
        
        if games_df.empty:
            logger.warning(f"球員ID {player_id} 在 {season} 賽季的 {season_type} 沒有比賽記錄")
            return pd.DataFrame()
        
        # 添加賽季和比賽類型列
        games_df['SEASON'] = season
        games_df['SEASON_TYPE'] = season_type
        
        logger.info(f"找到 {len(games_df)} 場 {season_type} 比賽記錄")
        return games_df
    
    except Exception as e:
        logger.error(f"獲取球員ID {player_id} 在 {season_year} 賽季的 {season_type} 比賽記錄時出錯: {e}")
        return pd.DataFrame()

def get_player_pass_data_for_game(player_id, game_date, season_year, season_type="Regular Season"):
    """獲取指定球員在特定日期比賽的傳球數據"""
    try:
        # 將年份格式轉換為NBA API需要的格式 (例如: 2023-24)
        season = f"{season_year}-{str(season_year + 1)[-2:]}"
        
        # 定義實際的API請求函數
        def fetch_pass_data():
            player_pass = playerdashptpass.PlayerDashPtPass(
                player_id=player_id,
                team_id=0,
                season=season,
                season_type_all_star=season_type,
                date_from_nullable=game_date,
                date_to_nullable=game_date,
                timeout=45
            )
            return player_pass.get_data_frames()
        
        # 使用速率限制和智能重試
        data_frames = rate_limited_request(
            smart_retry,
            fetch_pass_data,
            max_retries=3,
            base_delay=2
        )
        
        # 傳球給隊友的數據
        pass_made_to_teammates = data_frames[0] if len(data_frames) > 0 else pd.DataFrame()
        
        if not pass_made_to_teammates.empty:
            # 添加日期、賽季和比賽類型列
            pass_made_to_teammates['GAME_DATE'] = game_date
            pass_made_to_teammates['SEASON'] = season
            pass_made_to_teammates['SEASON_TYPE'] = season_type
            pass_made_to_teammates['PLAYER_ID'] = player_id
            
            # 重新排序列，使PASS_TEAMMATE_PLAYER_ID緊鄰PLAYER_ID
            all_columns = pass_made_to_teammates.columns.tolist()
            special_cols = ['PLAYER_ID', 'PASS_TEAMMATE_PLAYER_ID', 'GAME_DATE', 'SEASON', 'SEASON_TYPE']
            remaining_cols = [col for col in all_columns if col not in special_cols]
            new_order = ['PLAYER_ID', 'PASS_TEAMMATE_PLAYER_ID', 'GAME_DATE', 'SEASON', 'SEASON_TYPE'] + remaining_cols
            pass_made_to_teammates = pass_made_to_teammates[new_order]
            
        return pass_made_to_teammates
    
    except Exception as e:
        logger.error(f"獲取球員ID {player_id} 在 {game_date} 的傳球數據時出錯: {e}")
        return pd.DataFrame()

def get_player_pass_data_with_cache(player_id, game_date, season_year, season_type, cache_dir):
    """帶緩存的球員傳球數據獲取"""
    # 生成緩存鍵和緩存文件路徑
    cache_key = get_cache_key(player_id, game_date, season_year, season_type)
    cache_file = os.path.join(cache_dir, f"{cache_key}.pkl")
    
    # 檢查緩存是否存在
    if os.path.exists(cache_file):
        try:
            with open(cache_file, 'rb') as f:
                data = pickle.load(f)
                logger.info(f"從緩存讀取 {game_date} 的傳球數據")
                return data
        except Exception as e:
            logger.warning(f"讀取緩存文件 {cache_file} 失敗: {e}")
    
    # 如果緩存不存在或讀取失敗，則從API獲取數據
    data = get_player_pass_data_for_game(player_id, game_date, season_year, season_type)
    
    # 保存到緩存
    if not data.empty:
        try:
            os.makedirs(cache_dir, exist_ok=True)
            with open(cache_file, 'wb') as f:
                pickle.dump(data, f)
        except Exception as e:
            logger.warning(f"保存緩存文件 {cache_file} 失敗: {e}")
    
    return data

def process_player_concurrent(player, season_year, output_dir, season_dir, cache_dir, max_workers=3):
    """使用並行處理單個球員的所有傳球數據"""
    player_id = player['id']
    player_name = player['full_name'].replace(" ", "_")
    
    logger.info(f"開始處理球員: {player_name} (ID: {player_id}) - 賽季 {season_year}-{str(season_year + 1)[-2:]}")
    
    all_pass_data = []
    season_types = ["Regular Season", "Playoffs"]
    
    for season_type in season_types:
        logger.info(f"處理 {season_type} 比賽...")
        
        # 獲取該類型的所有比賽
        games_df = get_player_games_in_season(player_id, season_year, season_type)
        
        if games_df.empty:
            continue
        
        # 創建任務列表
        tasks = []
        for i, game in games_df.iterrows():
            try:
                game_date_str = game['GAME_DATE']
                game_date = datetime.strptime(game_date_str, '%b %d, %Y')
                formatted_date = game_date.strftime('%Y-%m-%d')
                
                # 添加任務
                tasks.append((player_id, formatted_date, season_year, season_type, game['Game_ID']))
            except Exception as e:
                logger.error(f"處理比賽日期 {game['GAME_DATE']} 時出錯: {e}")
        
        # 使用線程池並行處理
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
            # 提交所有任務
            future_to_task = {}
            for task in tasks:
                future = executor.submit(
                    get_player_pass_data_with_cache,
                    task[0],  # player_id
                    task[1],  # formatted_date
                    task[2],  # season_year
                    task[3],  # season_type
                    cache_dir
                )
                future_to_task[future] = task
            
            # 處理結果
            for future in concurrent.futures.as_completed(future_to_task):
                task = future_to_task[future]
                try:
                    pass_data = future.result()
                    if not pass_data.empty:
                        # 添加比賽ID
                        pass_data['GAME_ID'] = task[4]
                        all_pass_data.append(pass_data)
                        logger.info(f"成功獲取 {len(pass_data)} 條傳球記錄 (日期: {task[1]})")
                except Exception as e:
                    logger.error(f"處理比賽日期 {task[1]} 時出錯: {e}")
    
    # 合併所有數據
    if all_pass_data:
        combined_df = pd.concat(all_pass_data, ignore_index=True)
        
        # 保存到年份資料夾中的CSV文件
        player_file = os.path.join(season_dir, f"{player_name}_{player_id}.csv")
        combined_df.to_csv(player_file, index=False)
        logger.info(f"球員 {player_name} 的數據已保存到 {player_file}")
        
        return combined_df
    else:
        logger.warning(f"沒有找到球員 {player_name} (ID: {player_id}) 的任何傳球數據")
        return pd.DataFrame()

def process_players_batch(players_batch, season_year, base_output_dir, season_dir, cache_dir, progress):
    """批次處理多個球員"""
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        # 提交所有任務
        future_to_player = {}
        for player in players_batch:
            player_id = player['id']
            # 如果球員已處理，則跳過
            if player_id in progress['processed_players']:
                continue
            # 提交任務
            future = executor.submit(
                process_player_concurrent, 
                player, 
                season_year, 
                base_output_dir, 
                season_dir,
                cache_dir
            )
            future_to_player[future] = player
        
        # 處理結果
        for future in concurrent.futures.as_completed(future_to_player):
            player = future_to_player[future]
            player_id = player['id']
            player_name = player['full_name']
            
            try:
                future.result()  # 獲取結果，忽略返回值
                # 更新進度
                progress['processed_players'].add(player_id)
                logger.info(f"成功處理球員: {player_name} (ID: {player_id})")
            except Exception as e:
                logger.error(f"處理球員 {player_name} (ID: {player_id}) 時出錯: {e}")
                progress['failed_players'].add(player_id)

def merge_all_csv(season_dir, output_dir, season_year):
    """合併所有球員的CSV文件為一個總表"""
    try:
        all_data = []
        csv_files = [f for f in os.listdir(season_dir) if f.endswith('.csv')]
        
        if not csv_files:
            logger.warning(f"在 {season_dir} 中沒有找到CSV文件")
            return
        
        for csv_file in csv_files:
            file_path = os.path.join(season_dir, csv_file)
            df = pd.read_csv(file_path)
            all_data.append(df)
        
        if all_data:
            merged_df = pd.concat(all_data, ignore_index=True)
            merged_file = os.path.join(output_dir, f"all_players_pass_data_{season_year}.csv")
            merged_df.to_csv(merged_file, index=False)
            logger.info(f"所有球員的傳球數據已合併並保存到 {merged_file}")
        else:
            logger.warning("沒有數據可合併")
    
    except Exception as e:
        logger.error(f"合併CSV文件時出錯: {e}")

def process_season(season_year, json_file_pattern, base_output_dir):
    """處理單個賽季的所有球員數據"""
    # 設置賽季格式
    season_str = f"{season_year}-{str(season_year + 1)[-2:]}"
    
    # 構建JSON文件名
    json_file = json_file_pattern.format(season_str=season_str)
    
    if not os.path.exists(json_file):
        logger.error(f"找不到球員列表文件: {json_file}")
        return False
    
    # 創建年份子目錄
    season_dir = os.path.join(base_output_dir, season_str)
    if not os.path.exists(season_dir):
        os.makedirs(season_dir)
    
    # 創建緩存目錄
    cache_dir = os.path.join(base_output_dir, "cache", season_str)
    if not os.path.exists(cache_dir):
        os.makedirs(cache_dir)
    
    # 進度文件路徑
    progress_file = os.path.join(base_output_dir, f"progress_{season_year}.pkl")
    
    # 加載球員列表
    players = load_player_list(json_file, season_str)
    if not players:
        logger.error(f"沒有找到符合條件的球員，跳過賽季 {season_str}")
        return False
    
    # 加載處理進度
    progress = load_progress(progress_file)
    
    # 將球員分成小批次處理
    batch_size = 5  # 每批處理的球員數量
    for i in range(0, len(players), batch_size):
        batch = players[i:i+batch_size]
        logger.info(f"處理第 {i//batch_size + 1} 批球員 ({i+1} 到 {min(i+batch_size, len(players))})")
        
        # 處理這批球員
        process_players_batch(batch, season_year, base_output_dir, season_dir, cache_dir, progress)
        
        # 保存進度
        save_progress(progress, progress_file)
    
    # 合併所有CSV
    merge_all_csv(season_dir, base_output_dir, season_year)
    
    # 最終保存進度
    save_progress(progress, progress_file)
    
    logger.info(f"賽季 {season_str} 處理完成! 成功處理 {len(progress['processed_players'])} 名球員，失敗 {len(progress['failed_players'])} 名球員")
    
    # 如果有失敗的球員，輸出列表
    if progress['failed_players']:
        failed_ids = list(progress['failed_players'])
        failed_names = [next((p['full_name'] for p in players if p['id'] == pid), str(pid)) for pid in failed_ids]
        logger.info(f"賽季 {season_str} 失敗的球員列表:")
        for name, pid in zip(failed_names, failed_ids):
            logger.info(f"  - {name} (ID: {pid})")
    
    return True

def main():
    # 優化NBA API的請求頭
    optimize_nba_api_headers()
    
    # 設定多個賽季
    seasons = [2014]  # 可以根據需要調整賽季列表
    
    # JSON文件模式，使用格式化字符串替換賽季
    json_file_pattern = "nba_players_{season_str}_detailed_final.json"
    
    # 設定輸出目錄
    base_output_dir = "nba_pass_data"
    
    # 創建輸出目錄
    if not os.path.exists(base_output_dir):
        os.makedirs(base_output_dir)
    
    # 處理每個賽季
    for season_year in seasons:
        logger.info(f"開始處理賽季 {season_year}-{str(season_year + 1)[-2:]}")
        success = process_season(season_year, json_file_pattern, base_output_dir)
        
        if not success:
            logger.warning(f"賽季 {season_year}-{str(season_year + 1)[-2:]} 處理中斷，將繼續處理下一個賽季")
    
    logger.info("所有指定賽季處理完成!")

if __name__ == "__main__":
    # 設置日誌
    log_dir = "logs"
    logger = setup_logging(log_dir)
    
    try:
        main()
    except Exception as e:
        logger.critical(f"程序執行時發生嚴重錯誤: {e}")
        import traceback
        logger.critical(traceback.format_exc())
