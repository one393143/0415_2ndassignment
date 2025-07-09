from nba_api.stats.endpoints import leaguedashteamstats, leaguestandings, teamgamelog
from nba_api.stats.static import teams
import pandas as pd
import time
import os

# 定義要抓取的賽季
seasons = [
    '2015-16', '2016-17', '2017-18', '2018-19', '2019-20',
    '2020-21', '2021-22', '2022-23', '2023-24','2024-25'
]

# 獲取所有球隊資訊
nba_teams = teams.get_teams()
team_dict = {team['id']: team['full_name'] for team in nba_teams}

# 定義要抓取的數據類型
season_types = ['Regular Season', 'Playoffs']

# 定義要抓取的測量類型
measure_types = [
    'Base',
    'Advanced',
    'Misc',
    'Four Factors',
    'Scoring',
    'Opponent',
    'Defense'
]

# 創建資料夾用於存儲臨時數據
os.makedirs('temp_data', exist_ok=True)

def determine_playoff_round(wins, season):
    """
    基於季後賽勝場數和賽季來確定球隊達到的季後賽輪次
    
    參數:
    wins (int): 球隊在季後賽中獲得的勝場數
    season (str): 賽季，例如 '2015-16'
    
    返回:
    str: 季後賽輪次描述
    """
    if wins == 0:
        return "未進入季後賽" if season < '2020-21' else "可能為附加賽"
    
    # 從2020-21賽季開始，NBA引入了附加賽
    if season >= '2020-21':
        if wins == 1:
            return "附加賽"
        elif wins <= 4:  # 首輪需要4場勝利
            return "首輪"
        elif wins <= 8:  # 首輪4勝 + 半決賽4勝
            return "分區半決賽"
        elif wins <= 12:  # 首輪4勝 + 半決賽4勝 + 分區決賽4勝
            return "分區決賽"
        else:  # 首輪4勝 + 半決賽4勝 + 分區決賽4勝 + 總決賽(進行中)
            return "總決賽"
    else:  # 2015-16 到 2019-20
        if wins <= 4:
            return "首輪"
        elif wins <= 8:
            return "分區半決賽"
        elif wins <= 12:
            return "分區決賽"
        else:
            return "總決賽"


# 為每個賽季處理數據
for season in seasons:
    print(f"\n正在處理 {season} 賽季的數據...")
    
    # 抓取聯盟排名數據
    print(f"正在抓取 {season} 的聯盟排名數據...")
    try:
        standings = leaguestandings.LeagueStandings(
            league_id='00',
            season=season,
            season_type='Regular Season'
        )
        
        df_standings = standings.get_data_frames()[0]
        df_standings['SEASON'] = season
        
        # 保存當前賽季的排名數據
        df_standings.to_csv(f'temp_data/standings_{season}.csv', index=False)
        print(f"  {season} 聯盟排名數據已保存")
        
        time.sleep(0.1)
    except Exception as e:
        print(f"抓取 {season} 的聯盟排名數據時出錯: {e}")
    
    # 抓取每支球隊的季後賽進程數據
    playoff_progress_data = []

    for team_id, team_name in team_dict.items():
        print(f"  正在抓取 {team_name} 的季後賽進程數據...")
        
        try:
            game_log = teamgamelog.TeamGameLog(
                team_id=team_id,
                season=season,
                season_type_all_star='Playoffs'
            )
            
            df_games = game_log.get_data_frames()[0]
            
            if df_games.empty:
                # 檢查是否有附加賽數據（僅適用於2020-21賽季之後）
                if season >= '2020-21':
                    play_in_game_log = teamgamelog.TeamGameLog(
                        team_id=team_id,
                        season=season,
                        season_type_all_star='PlayIn'  # 附加賽類型
                    )
                    play_in_games = play_in_game_log.get_data_frames()[0]
                    
                    if not play_in_games.empty:
                        play_in_wins = sum(play_in_games['WL'] == 'W')
                        play_in_losses = sum(play_in_games['WL'] == 'L')
                        last_game_date = play_in_games['GAME_DATE'].iloc[0]
                        
                        playoff_progress_data.append({
                            'SEASON': season,
                            'TEAM_ID': team_id,
                            'TEAM_NAME': team_name,
                            'PLAYOFF_GAMES': len(play_in_games),
                            'PLAYOFF_ROUND': "附加賽",
                            'WINS': play_in_wins,
                            'LOSSES': play_in_losses,
                            'LAST_GAME_DATE': last_game_date,
                            'ADVANCED_TO_PLAYOFFS': play_in_wins > 0 and play_in_losses == 0
                        })
                        continue
                
                # 如果沒有季後賽或附加賽數據
                playoff_progress_data.append({
                    'SEASON': season,
                    'TEAM_ID': team_id,
                    'TEAM_NAME': team_name,
                    'PLAYOFF_GAMES': 0,
                    'PLAYOFF_ROUND': "未進入季後賽",
                    'WINS': 0,
                    'LOSSES': 0,
                    'LAST_GAME_DATE': None,
                    'ADVANCED_TO_PLAYOFFS': False
                })
            else:
                num_playoff_games = len(df_games)
                wins = sum(df_games['WL'] == 'W')
                losses = sum(df_games['WL'] == 'L')
                last_game_date = df_games['GAME_DATE'].iloc[0]
                playoff_round = determine_playoff_round(wins, season)
                
                # 檢查是否為總冠軍
                is_champion = False
                if playoff_round == "總決賽" and wins >= 16:  # 4+4+4+4=16場勝利代表贏得總冠軍
                    # 檢查最後一場比賽是否獲勝
                    last_game = df_games.iloc[0]  # 最近的比賽
                    if last_game['WL'] == 'W':
                        is_champion = True
                
                playoff_progress_data.append({
                    'SEASON': season,
                    'TEAM_ID': team_id,
                    'TEAM_NAME': team_name,
                    'PLAYOFF_GAMES': num_playoff_games,
                    'PLAYOFF_ROUND': playoff_round,
                    'WINS': wins,
                    'LOSSES': losses,
                    'LAST_GAME_DATE': last_game_date,
                    'IS_CHAMPION': is_champion
                })
            
            time.sleep(1)
        except Exception as e:
            print(f"  抓取 {team_name} 的季後賽進程數據時出錯: {e}")
            playoff_progress_data.append({
                'SEASON': season,
                'TEAM_ID': team_id,
                'TEAM_NAME': team_name,
                'PLAYOFF_GAMES': None,
                'PLAYOFF_ROUND': "抓取出錯",
                'WINS': None,
                'LOSSES': None,
                'LAST_GAME_DATE': None,
                'IS_CHAMPION': False
            })

    
    # 保存當前賽季的季後賽進程數據
    playoff_progress_df = pd.DataFrame(playoff_progress_data)
    playoff_progress_df.to_csv(f'temp_data/playoff_progress_{season}.csv', index=False)
    print(f"  {season} 季後賽進程數據已保存")
    
    # 抓取每種賽季類型的團隊統計數據
    for season_type in season_types:
        print(f"正在抓取 {season} {season_type} 的團隊統計數據...")
        
        # 為每個測量類型創建字典
        measure_type_dfs = {}
        
        for measure_type in measure_types:
            print(f"  正在抓取 {measure_type} 數據...")
            
            try:
                team_stats = leaguedashteamstats.LeagueDashTeamStats(
                    season=season,
                    season_type_all_star=season_type,
                    measure_type_detailed_defense=measure_type,
                    per_mode_detailed='PerGame',  # 使用每場平均數據
                    plus_minus='Y',
                    rank='Y',
                    pace_adjust='N',
                    league_id_nullable='00'
                )
                
                df = team_stats.get_data_frames()[0]
                
                # 確保數據不為空
                if not df.empty:
                    # 添加元數據
                    df['SEASON'] = season
                    df['SEASON_TYPE'] = season_type
                    df['MEASURE_TYPE'] = measure_type
                    
                    # 存儲到字典中
                    measure_type_dfs[measure_type] = df
                
                time.sleep(0.1)
            except Exception as e:
                print(f"抓取 {season} {season_type} 的 {measure_type} 數據時出錯: {e}")
                continue
        
        # 合併不同測量類型的數據
        if measure_type_dfs:
            # 首先使用 Base 測量類型作為基礎
            if 'Base' in measure_type_dfs:
                base_df = measure_type_dfs['Base']
                
                # 定義要保留的基礎欄位
                base_columns = ['TEAM_ID', 'TEAM_NAME', 'GP', 'W', 'L', 'W_PCT', 
                               'MIN', 'FGM', 'FGA', 'FG_PCT', 'FG3M', 'FG3A', 
                               'FG3_PCT', 'FTM', 'FTA', 'FT_PCT', 'OREB', 'DREB', 
                               'REB', 'AST', 'TOV', 'STL', 'BLK', 'BLKA', 'PF', 
                               'PFD', 'PTS', 'PLUS_MINUS', 'SEASON', 'SEASON_TYPE']
                
                # 創建最終的DataFrame
                final_df = base_df[base_columns].copy()
                
                # 添加其他測量類型的欄位
                for measure_type, df in measure_type_dfs.items():
                    if measure_type != 'Base':
                        # 排除已經在final_df中的欄位
                        existing_columns = final_df.columns.tolist()
                        new_columns = [col for col in df.columns if col not in existing_columns 
                                      and col not in ['TEAM_ID', 'TEAM_NAME', 'GP', 'W', 'L', 'W_PCT', 'SEASON', 'SEASON_TYPE', 'MEASURE_TYPE']]
                        
                        # 合併新欄位
                        if new_columns:
                            # 以TEAM_ID和SEASON作為合併鍵
                            merge_df = df[['TEAM_ID', 'SEASON'] + new_columns]
                            final_df = pd.merge(final_df, merge_df, on=['TEAM_ID', 'SEASON'], how='left')
                
                # 保存合併後的數據
                output_filename = f'temp_data/{season_type.lower().replace(" ", "_")}_{season}.csv'
                final_df.to_csv(output_filename, index=False)
                print(f"  {season} {season_type} 數據已保存到 {output_filename}")
            else:
                print(f"  {season} {season_type} 缺少基礎(Base)測量類型數據，無法合併")

# 合併所有賽季的數據
print("\n正在合併所有賽季的數據...")

# 合併例行賽數據
regular_season_files = [f for f in os.listdir('temp_data') if f.startswith('regular_season_')]
if regular_season_files:
    regular_season_dfs = [pd.read_csv(f'temp_data/{file}') for file in regular_season_files]
    all_regular_season_df = pd.concat(regular_season_dfs, ignore_index=True)
    all_regular_season_df.to_csv('nba_regular_season_stats_2015_to_2024.csv', index=False)
    print("所有例行賽數據已合併保存")

# 合併季後賽數據
playoff_files = [f for f in os.listdir('temp_data') if f.startswith('playoffs_')]
if playoff_files:
    playoff_dfs = [pd.read_csv(f'temp_data/{file}') for file in playoff_files]
    all_playoff_df = pd.concat(playoff_dfs, ignore_index=True)
    all_playoff_df.to_csv('nba_playoff_stats_2015_to_2024.csv', index=False)
    print("所有季後賽數據已合併保存")

# 合併排名數據
standings_files = [f for f in os.listdir('temp_data') if f.startswith('standings_')]
if standings_files:
    standings_dfs = [pd.read_csv(f'temp_data/{file}') for file in standings_files]
    all_standings_df = pd.concat(standings_dfs, ignore_index=True)
    all_standings_df.to_csv('nba_league_standings_2015_to_2024.csv', index=False)
    print("所有聯盟排名數據已合併保存")

# 合併季後賽進程數據
playoff_progress_files = [f for f in os.listdir('temp_data') if f.startswith('playoff_progress_')]
if playoff_progress_files:
    playoff_progress_dfs = [pd.read_csv(f'temp_data/{file}') for file in playoff_progress_files]
    all_playoff_progress_df = pd.concat(playoff_progress_dfs, ignore_index=True)
    all_playoff_progress_df.to_csv('nba_playoff_progress_2015_to_2024.csv', index=False)
    print("所有季後賽進程數據已合併保存")

print("\n數據抓取和合併完成!")
