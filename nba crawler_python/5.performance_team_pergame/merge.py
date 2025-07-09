import os
import pandas as pd
import logging
from datetime import datetime

# 設置日誌
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger()

def merge_all_seasons_data(seasons_dir='seasons', output_dir='output'):
    """
    合併所有賽季和賽季類型的數據
    
    參數:
    seasons_dir (str): 賽季數據目錄
    output_dir (str): 輸出目錄
    """
    # 確保輸出目錄存在
    os.makedirs(output_dir, exist_ok=True)
    
    # 儲存所有數據的列表
    all_seasons_data = []
    
    # 遍歷所有賽季目錄
    for season in os.listdir(seasons_dir):
        season_path = os.path.join(seasons_dir, season)
        
        # 確保是目錄，並排除隱藏文件
        if os.path.isdir(season_path) and not season.startswith('.'):
            # 遍歷賽季類型目錄
            for season_type in os.listdir(season_path):
                season_type_path = os.path.join(season_path, season_type)
                
                # 確保是目錄，並排除隱藏文件
                if os.path.isdir(season_type_path) and not season_type.startswith('.'):
                    # 遍歷該目錄下的所有 CSV 文件
                    for filename in os.listdir(season_type_path):
                        if filename.endswith('.csv') and not filename.startswith('.'):
                            file_path = os.path.join(season_type_path, filename)
                            
                            try:
                                # 讀取 CSV 文件
                                df = pd.read_csv(file_path)
                                
                                # 如果 DataFrame 不為空
                                if not df.empty:
                                    logger.info(f"成功讀取: {file_path}")
                                    all_seasons_data.append(df)
                                else:
                                    logger.warning(f"文件為空: {file_path}")
                            
                            except Exception as e:
                                logger.error(f"讀取 {file_path} 時出錯: {e}")
    
    # 如果有數據，則合併
    if all_seasons_data:
        # 合併所有數據
        combined_df = pd.concat(all_seasons_data, ignore_index=True)
        
        # 去除重複記錄
        combined_df = combined_df.drop_duplicates(subset=['GAME_ID', 'TEAM_ID'])
        
        # 生成輸出文件名（包含當前日期）
        output_filename = f"all_seasons_all_games_team_stats_{datetime.now().strftime('%Y%m%d')}.csv"
        output_path = os.path.join(output_dir, output_filename)
        
        # 保存文件
        combined_df.to_csv(output_path, index=False)
        
        logger.info(f"成功合併所有賽季數據，共 {len(combined_df)} 條記錄")
        logger.info(f"已保存到: {output_path}")
    
    else:
        logger.warning("未找到任何數據")

def main():
    merge_all_seasons_data()

if __name__ == "__main__":
    main()
