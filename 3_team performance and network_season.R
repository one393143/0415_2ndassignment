
# 清理環境
rm(list = ls())

# 載入必要的套件
library(readr)
library(dplyr)
library(stringr)
library(purrr)
library(tidyr)

# 自動設定工作目錄
current_path <- rstudioapi::getActiveDocumentContext()$path
if (!is.null(current_path) && current_path != "") {
  setwd(dirname(current_path))
} else {
  stop("無法自動檢測 R 檔案的路徑")
}

# 確認當前工作目錄
cat("當前工作目錄：", getwd(), "\n")

# 檢查data資料夾是否存在
if (!dir.exists("data")) {
  stop("data資料夾不存在，請確認資料夾結構")
}

# ==================== 1. 匯入網絡指標數據 ====================
cat("正在匯入網絡指標數據...\n")

# 檢查網絡指標資料夾
network_path <- "data/network metrics_team_each game"
if (!dir.exists(network_path)) {
  stop("網絡指標資料夾不存在")
}

# 列出所有網絡指標檔案
network_files <- list.files(network_path, pattern = "network_metrics_.*\\.csv", full.names = TRUE)
cat("找到", length(network_files), "個網絡指標檔案\n")

# 匯入所有網絡指標檔案
network_data_list <- list()
for (file in network_files) {
  year <- str_extract(basename(file), "\\d{4}")
  cat("正在讀取", year, "年網絡數據...\n")
  
  tryCatch({
    data <- read_csv(file, show_col_types = FALSE)
    network_data_list[[year]] <- data
    cat("成功讀取", year, "年數據，共", nrow(data), "筆記錄\n")
  }, error = function(e) {
    cat("讀取", year, "年數據時發生錯誤：", e$message, "\n")
  })
}

# 合併所有網絡數據
if (length(network_data_list) > 0) {
  network_metrics <- bind_rows(network_data_list)
  cat("網絡指標數據合併完成，總共", nrow(network_metrics), "筆記錄\n")
} else {
  stop("無法讀取任何網絡指標數據")
}

# ==================== 2. 匯入球隊表現數據 ====================
cat("\n正在匯入球隊表現數據...\n")

# 檢查球隊表現資料夾
performance_path <- "data/performance_team"
if (!dir.exists(performance_path)) {
  stop("球隊表現資料夾不存在")
}

# 匯入例行賽統計
regular_season_file <- file.path(performance_path, "nba_regular_season_stats_2015_to_2024.csv")
if (file.exists(regular_season_file)) {
  regular_season_stats <- read_csv(regular_season_file, show_col_types = FALSE)
  cat("成功讀取例行賽統計數據，共", nrow(regular_season_stats), "筆記錄\n")
} else {
  cat("例行賽統計檔案不存在\n")
  regular_season_stats <- NULL
}

# 匯入季後賽統計
playoff_file <- file.path(performance_path, "nba_playoff_stats_2015_to_2024.csv")
if (file.exists(playoff_file)) {
  playoff_stats <- read_csv(playoff_file, show_col_types = FALSE)
  cat("成功讀取季後賽統計數據，共", nrow(playoff_stats), "筆記錄\n")
} else {
  cat("季後賽統計檔案不存在\n")
  playoff_stats <- NULL
}

# 匯入聯盟排名
standings_file <- file.path(performance_path, "nba_league_standings_2015_to_2024.csv")
if (file.exists(standings_file)) {
  league_standings <- read_csv(standings_file, show_col_types = FALSE)
  cat("成功讀取聯盟排名數據，共", nrow(league_standings), "筆記錄\n")
} else {
  cat("聯盟排名檔案不存在\n")
  league_standings <- NULL
}

# ==================== 3. 匯入球員逐場數據 ====================
cat("\n正在匯入球員逐場數據...\n")

# 檢查球員表現資料夾
player_path <- "data/performance_player_pergame"
if (!dir.exists(player_path)) {
  stop("球員表現資料夾不存在")
}

# 列出所有球員逐場檔案
player_files <- list.files(player_path, pattern = "\\d{4}-\\d{2}_player_game_data\\.csv", full.names = TRUE)
cat("找到", length(player_files), "個球員逐場數據檔案\n")

# 匯入所有球員逐場檔案
player_data_list <- list()
for (file in player_files) {
  season <- str_extract(basename(file), "\\d{4}-\\d{2}")
  cat("正在讀取", season, "賽季球員數據...\n")
  
  tryCatch({
    data <- read_csv(file, show_col_types = FALSE)
    player_data_list[[season]] <- data
    cat("成功讀取", season, "賽季數據，共", nrow(data), "筆記錄\n")
  }, error = function(e) {
    cat("讀取", season, "賽季數據時發生錯誤：", e$message, "\n")
  })
}

# 合併所有球員數據
if (length(player_data_list) > 0) {
  player_game_data <- bind_rows(player_data_list)
  cat("球員逐場數據合併完成，總共", nrow(player_game_data), "筆記錄\n")
} else {
  cat("無法讀取任何球員逐場數據\n")
  player_game_data <- NULL
}

# ==================== 4. 匯入團隊每場比賽統計數據 ====================
cat("\n正在匯入團隊每場比賽統計數據...\n")

# 檢查團隊每場比賽統計檔案
team_stats_file <- "data/performance_team_pergame/all_seasons_all_games_team_stats.csv"
if (file.exists(team_stats_file)) {
  team_game_stats <- read_csv(team_stats_file, show_col_types = FALSE)
  cat("成功讀取團隊每場比賽統計數據，共", nrow(team_game_stats), "筆記錄\n")
  
  # 顯示數據基本資訊
  cat("- 涵蓋賽季：", paste(unique(team_game_stats$SEASON), collapse = ", "), "\n")
  cat("- 球隊數：", length(unique(team_game_stats$TEAM_ID)), "\n")
  cat("- 例行賽場次：", sum(team_game_stats$SEASON_TYPE == "Regular Season", na.rm = TRUE), "\n")
  cat("- 季後賽場次：", sum(team_game_stats$SEASON_TYPE == "Playoffs", na.rm = TRUE), "\n")
  
  # 檢查數據欄位
  cat("- 欄位數：", ncol(team_game_stats), "\n")
  cat("- 主要欄位：", paste(head(names(team_game_stats), 10), collapse = ", "), "...\n")
  
} else {
  cat("團隊每場比賽統計檔案不存在，將使用球員數據進行彙整\n")
  team_game_stats <- NULL
}

# ==================== 5. 數據概覽 ====================
cat("\n==================== 數據匯入摘要 ====================\n")

# 網絡指標數據概覽
if (exists("network_metrics")) {
  cat("網絡指標數據：\n")
  cat("- 總記錄數：", nrow(network_metrics), "\n")
  cat("- 欄位數：", ncol(network_metrics), "\n")
  if ("season" %in% names(network_metrics)) {
    cat("- 涵蓋賽季：", paste(unique(network_metrics$season), collapse = ", "), "\n")
  }
  if ("team_abbr" %in% names(network_metrics)) {
    cat("- 球隊數：", length(unique(network_metrics$team_abbr)), "\n")
  }
}

# 球隊表現數據概覽
if (!is.null(regular_season_stats)) {
  cat("\n例行賽統計數據：\n")
  cat("- 總記錄數：", nrow(regular_season_stats), "\n")
  cat("- 欄位數：", ncol(regular_season_stats), "\n")
}

if (!is.null(league_standings)) {
  cat("\n聯盟排名數據：\n")
  cat("- 總記錄數：", nrow(league_standings), "\n")
  cat("- 欄位數：", ncol(league_standings), "\n")
}

# 球員逐場數據概覽
if (!is.null(player_game_data)) {
  cat("\n球員逐場數據：\n")
  cat("- 總記錄數：", nrow(player_game_data), "\n")
  cat("- 欄位數：", ncol(player_game_data), "\n")
  if ("SEASON" %in% names(player_game_data)) {
    cat("- 涵蓋賽季：", paste(unique(player_game_data$SEASON), collapse = ", "), "\n")
  }
}

# 團隊每場比賽數據概覽
if (!is.null(team_game_stats)) {
  cat("\n團隊每場比賽數據：\n")
  cat("- 總記錄數：", nrow(team_game_stats), "\n")
  cat("- 欄位數：", ncol(team_game_stats), "\n")
  cat("- 涵蓋賽季：", paste(unique(team_game_stats$SEASON), collapse = ", "), "\n")
  cat("- 球隊數：", length(unique(team_game_stats$TEAM_ID)), "\n")
  
  # 顯示數據樣本
  cat("\n團隊每場比賽數據樣本：\n")
  print(head(team_game_stats %>% dplyr::select(GAME_ID, TEAM_NAME, SEASON, PTS, AST, REB, FG_PCT), 5))
  
}

# ==================== 6. 檢查數據完整性 ====================
cat("\n==================== 數據完整性檢查 ====================\n")

# 檢查網絡指標數據的關鍵欄位
if (exists("network_metrics")) {
  cat("網絡指標數據關鍵欄位：\n")
  key_cols <- c("team_abbr", "game_date", "season", "nodes", "edges", "density")
  for (col in key_cols) {
    if (col %in% names(network_metrics)) {
      missing_count <- sum(is.na(network_metrics[[col]]))
      cat("- ", col, "：", missing_count, "個缺失值\n")
    } else {
      cat("- ", col, "：欄位不存在\n")
    }
  }
}

# 檢查團隊每場比賽數據的關鍵欄位
if (!is.null(team_game_stats)) {
  cat("\n團隊每場比賽數據關鍵欄位：\n")
  key_cols <- c("GAME_ID", "TEAM_ID", "SEASON", "PTS", "AST", "REB")
  for (col in key_cols) {
    if (col %in% names(team_game_stats)) {
      missing_count <- sum(is.na(team_game_stats[[col]]))
      cat("- ", col, "：", missing_count, "個缺失值\n")
    } else {
      cat("- ", col, "：欄位不存在\n")
    }
  }
  
  # 檢查比賽配對（每場比賽應該有兩支球隊）
  game_counts <- team_game_stats %>%
    group_by(GAME_ID) %>%
    summarise(team_count = n(), .groups = 'drop') %>%
    filter(team_count != 2)
  
  if (nrow(game_counts) > 0) {
    cat("- 發現", nrow(game_counts), "場比賽球隊數量異常（不等於2）\n")
  } else {
    cat("- 比賽配對數據正常\n")
  }
  
  # 顯示統計數據摘要
  cat("\n主要統計指標摘要：\n")
  stats_summary <- team_game_stats %>%
    summarise(
      平均得分 = round(mean(PTS, na.rm = TRUE), 1),
      平均助攻 = round(mean(AST, na.rm = TRUE), 1),
      平均籃板 = round(mean(REB, na.rm = TRUE), 1),
      平均失誤 = round(mean(TO, na.rm = TRUE), 1),
      平均投籃命中率 = round(mean(FG_PCT, na.rm = TRUE), 3)
    )
  print(stats_summary)
}

cat("\n數據匯入完成！\n")
cat("您現在可以開始進行網絡分析。\n")






# ==================== 網絡指標與球隊表現關聯分析 ====================
cat("\n==================== 開始網絡分析 ====================\n")

# 載入額外需要的套件
if (!require(corrplot)) install.packages("corrplot")
if (!require(ggplot2)) install.packages("ggplot2")
if (!require(gridExtra)) install.packages("gridExtra")
if (!require(factoextra)) install.packages("factoextra")

library(corrplot)
library(ggplot2)
library(gridExtra)
library(factoextra)  # 用於主成分分析可視化

# ==================== 修正後的數據預處理和匹配 ====================
cat("正在進行數據預處理和匹配...\n")

# 1. 處理網絡指標數據 - 計算賽季平均值
cat("\n計算各隊各賽季的網絡指標平均值...\n")

# 檢查season_type欄位是否存在
if ("season_type" %in% names(network_metrics)) {
  cat("發現season_type欄位，將篩選例行賽數據...\n")
  # 篩選例行賽數據
  network_metrics_regular <- network_metrics %>%
    filter(tolower(season_type) == "regular season" | 
             tolower(season_type) == "regular" |
             is.na(season_type))  # 如果沒有標記，假設為例行賽
} else {
  cat("未發現season_type欄位，使用所有網絡指標數據...\n")
  network_metrics_regular <- network_metrics
}

# 確認網絡指標中的關鍵欄位
cat("檢查網絡指標數據中的關鍵欄位...\n")
network_key_cols <- c("team_abbr", "season")
missing_cols <- network_key_cols[!network_key_cols %in% names(network_metrics_regular)]

if (length(missing_cols) > 0) {
  cat("警告：網絡指標數據缺少以下關鍵欄位：", paste(missing_cols, collapse = ", "), "\n")
  stop("無法繼續分析，請確保網絡指標數據包含team_abbr和season欄位")
}

# 計算賽季平均網絡指標
network_season_avg <- network_metrics_regular %>%
  group_by(team_abbr, season) %>%
  summarise(
    # 基本網絡指標
    nodes = mean(nodes, na.rm = TRUE),
    edges = mean(edges, na.rm = TRUE),
    density = mean(density, na.rm = TRUE),
    
    # 連通性指標
    vertex_connectivity = mean(vertex_connectivity, na.rm = TRUE),
    edge_connectivity = mean(edge_connectivity, na.rm = TRUE),
    components = mean(components, na.rm = TRUE),
    max_component_size = mean(max_component_size, na.rm = TRUE),
    
    # 中心化指標
    in_degree_centralization = mean(in_degree_centralization, na.rm = TRUE),
    out_degree_centralization = mean(out_degree_centralization, na.rm = TRUE),
    betweenness_centralization = mean(betweenness_centralization, na.rm = TRUE),
    eigenvector_centralization = mean(eigenvector_centralization, na.rm = TRUE),
    
    # 社群模組化指標
    walktrap_modularity = mean(walktrap_modularity, na.rm = TRUE),
    louvain_modularity = mean(louvain_modularity, na.rm = TRUE),
    best_modularity = mean(best_modularity, na.rm = TRUE),
    
    # 計算樣本數（該隊該賽季的比賽數）
    game_count = n(),
    
    .groups = 'drop'
  )

cat("成功計算", nrow(network_season_avg), "筆賽季平均網絡指標\n")
cat("- 涵蓋賽季：", paste(sort(unique(network_season_avg$season)), collapse = ", "), "\n")
cat("- 涵蓋球隊：", length(unique(network_season_avg$team_abbr)), "支\n")


# 2. 處理例行賽團隊表現數據
cat("\n處理例行賽團隊表現數據...\n")

# 檢查例行賽統計數據
if (is.null(regular_season_stats)) {
  cat("錯誤：例行賽統計數據不可用\n")
  stop("無法繼續分析，請確保例行賽統計數據已正確載入")
}

# 創建NBA球隊縮寫與全名的映射表
# 創建NBA球隊縮寫與全名的映射表
team_mapping <- data.frame(
  abbr = c("ATL", "BOS", "BKN", "CHI", "CHA", "CLE", "DAL", "DEN", "DET", "GSW",
           "HOU", "IND", "LAC", "LAL", "MEM", "MIA", "MIL", "MIN", "NOP", "NYK",
           "OKC", "ORL", "PHI", "PHX", "POR", "SAC", "SAS", "TOR", "UTA", "WAS"),
  full_name = c("Atlanta Hawks", "Boston Celtics", "Brooklyn Nets", "Chicago Bulls", 
                "Charlotte Hornets", "Cleveland Cavaliers", "Dallas Mavericks", 
                "Denver Nuggets", "Detroit Pistons", "Golden State Warriors",
                "Houston Rockets", "Indiana Pacers", "LA Clippers", "Los Angeles Lakers", 
                "Memphis Grizzlies", "Miami Heat", "Milwaukee Bucks", "Minnesota Timberwolves", 
                "New Orleans Pelicans", "New York Knicks", "Oklahoma City Thunder", 
                "Orlando Magic", "Philadelphia 76ers", "Phoenix Suns", "Portland Trail Blazers", 
                "Sacramento Kings", "San Antonio Spurs", "Toronto Raptors", "Utah Jazz", 
                "Washington Wizards")
)


# 顯示映射表
cat("球隊縮寫映射表（部分）：\n")
print(head(team_mapping, 10))

# 3. 合併網絡指標和球隊表現數據
cat("\n合併網絡指標和球隊表現數據...\n")

# 統一欄位名稱以便匹配
network_season_avg_clean <- network_season_avg %>%
  rename(TEAM_ABBREVIATION = team_abbr, SEASON = season)

# 使用映射表將網絡數據中的縮寫轉換為全名
network_season_avg_with_fullname <- network_season_avg_clean %>%
  left_join(team_mapping, by = c("TEAM_ABBREVIATION" = "abbr")) %>%
  rename(TEAM_FULLNAME = full_name)

# 檢查轉換結果
cat("網絡數據轉換後的樣本：\n")
print(head(network_season_avg_with_fullname %>% 
             dplyr::select(TEAM_ABBREVIATION, TEAM_FULLNAME, SEASON, density), 5))

# 檢查是否有未匹配的球隊
unmatched_teams <- network_season_avg_with_fullname %>% 
  filter(is.na(TEAM_FULLNAME)) %>% 
  pull(TEAM_ABBREVIATION) %>% 
  unique()

if (length(unmatched_teams) > 0) {
  cat("警告：以下球隊縮寫未能匹配到全名：", paste(unmatched_teams, collapse = ", "), "\n")
}

# 檢查 regular_season_stats 的欄位名稱
cat("例行賽統計數據的欄位名稱：\n")
print(names(regular_season_stats))

# 假設 regular_season_stats 中球隊名稱的欄位是 TEAM_NAME 或其他名稱
# 我們需要先檢查實際的欄位名稱，然後再進行合併

# 嘗試查看 regular_season_stats 的前幾行數據
cat("\n例行賽統計數據樣本：\n")
head(regular_season_stats %>% dplyr::select(1:5), 5)

# 根據檢查結果修改合併代碼
# 假設 regular_season_stats 中球隊名稱的欄位是 TEAM_NAME
merged_data <- network_season_avg_with_fullname %>%
  inner_join(
    regular_season_stats,
    by = c("TEAM_FULLNAME" = "TEAM_NAME", "SEASON" = "SEASON")
  )

cat("數據匹配完成，共", nrow(merged_data), "筆記錄\n")


# 檢查匹配結果
if (nrow(merged_data) == 0) {
  cat("警告：沒有匹配到任何數據，檢查匹配條件...\n")
  
  # 嘗試不考慮賽季的匹配
  merged_data_team_only <- network_season_avg_with_fullname %>%
    inner_join(
      regular_season_stats,
      by = c("TEAM_FULLNAME" = "TEAM_ABBREVIATION")
    )
  
  cat("僅使用球隊名稱匹配後，共", nrow(merged_data_team_only), "筆記錄\n")
  
  if (nrow(merged_data_team_only) > 0) {
    # 檢查賽季格式
    cat("\n網絡數據中的賽季格式：\n")
    print(sort(unique(network_season_avg_with_fullname$SEASON)))
    
    cat("\n表現數據中的賽季格式：\n")
    print(sort(unique(regular_season_stats$SEASON)))
    
    # 嘗試標準化賽季格式
    cat("\n嘗試標準化賽季格式...\n")
    
    # 將賽季轉換為年份
    network_season_avg_with_fullname$SEASON_YEAR <- as.numeric(substr(network_season_avg_with_fullname$SEASON, 1, 4))
    regular_season_stats$SEASON_YEAR <- as.numeric(substr(regular_season_stats$SEASON, 1, 4))
    
    # 使用年份進行匹配
    merged_data <- network_season_avg_with_fullname %>%
      inner_join(
        regular_season_stats,
        by = c("TEAM_FULLNAME" = "TEAM_ABBREVIATION", "SEASON_YEAR" = "SEASON_YEAR")
      )
    
    cat("使用標準化賽季年份匹配後，共", nrow(merged_data), "筆記錄\n")
  }
  
  if (nrow(merged_data) == 0) {
    stop("無法匹配數據，請檢查球隊名稱和賽季格式")
  }
} else {
  cat("匹配成功！繼續進行分析...\n")
}

# 顯示合併後的數據樣本
cat("\n合併後的數據樣本：\n")
print(head(merged_data %>% 
             dplyr::select(TEAM_ABBREVIATION, TEAM_FULLNAME, SEASON, density, any_of(c("PTS", "AST", "REB", "W", "L"))), 5))

# 顯示數據欄位
cat("\n合併後的數據欄位：\n")
cat(paste(names(merged_data), collapse = ", "), "\n")

# 檢查缺失值
missing_counts <- colSums(is.na(merged_data))
if (sum(missing_counts) > 0) {
  cat("\n發現缺失值：\n")
  print(missing_counts[missing_counts > 0])
}

cat("\n數據預處理和匹配完成！\n")










# ==================== 整合版籃球傳球網絡分析程式碼 ====================
# 載入所需套件（只載入一次）
library(tidyverse)  # 包含ggplot2
library(igraph)
library(lme4)
library(mediation)
library(psych)
library(factoextra)
library(corrplot)
library(grid)

# ==================== 1. 探索性數據分析 ====================
cat("\n==================== 1. 探索性數據分析 ====================\n")

# 選擇分析用的網絡指標
network_vars <- c("nodes", "edges", "density", "vertex_connectivity", 
                  "edge_connectivity", "components", "max_component_size",
                  "in_degree_centralization", "out_degree_centralization",
                  "betweenness_centralization", "eigenvector_centralization",
                  "walktrap_modularity", "louvain_modularity", "best_modularity")

# 選擇分析用的表現指標
performance_vars <- c("PTS", "AST", "REB", "FG_PCT", 
                      "STL", "BLK", "TO", "POSS")

# 檢查哪些變數實際存在
available_network_vars <- intersect(network_vars, names(merged_data))
available_performance_vars <- intersect(performance_vars, names(merged_data))

cat("可用的網絡指標（", length(available_network_vars), "個）：\n")
cat(paste(available_network_vars, collapse = ", "), "\n")

cat("\n可用的表現指標（", length(available_performance_vars), "個）：\n")
cat(paste(available_performance_vars, collapse = ", "), "\n\n")


# 重置圖形設備
dev.off()  # 關閉當前圖形設備
graphics.off()  # 關閉所有圖形設備
# ==================== 2. 中心化指標計算 ====================
cat("==================== 2. 中心化指標計算 ====================\n")

# 選擇centralization相關的變數
centralization_vars <- c("in_degree_centralization", 
                         "out_degree_centralization",
                         "betweenness_centralization", 
                         "eigenvector_centralization")

centralization_data <- merged_data[, centralization_vars]

# 檢查是否有缺失值
missing_count <- sum(is.na(centralization_data))
cat("中心化指標缺失值數量：", missing_count, "\n")

# 處理缺失值
centralization_data <- na.omit(centralization_data)

# 進行主成分分析
pca_result <- prcomp(centralization_data, 
                     center = TRUE,  # 標準化
                     scale. = TRUE)  # 使用標準差縮放

# 查看主成分解釋的方差比例
pca_summary <- summary(pca_result)
cat("\n主成分分析結果：\n")
print(pca_summary$importance)

# 可視化方差解釋
cat("\n繪製主成分方差解釋圖...\n")
fviz_eig(pca_result)

# 提取第一主成分作為綜合中心化指標（乘以-1使其方向與原始指標一致）
merged_data$centralization_pca <- pca_result$x[, 1] *-1

# 檢查新的中心化指標與原始指標的相關性
cor_with_pca <- cor(merged_data[, centralization_vars], 
                    merged_data$centralization_pca, 
                    use = "complete.obs")
cat("\n中心化指標與PCA第一主成分的相關性：\n")
print(cor_with_pca)

# 查看主成分的載荷矩陣
cat("\n主成分載荷矩陣：\n")
print(pca_result$rotation)



# 可視化中心化指標間的相關性
cat("\n繪製中心化指標相關性矩陣...\n")
corrplot(cor(merged_data[, centralization_vars], use = "complete.obs"), 
         method = "circle", 
         type = "upper")

# ==================== 3. 線性回歸分析 ====================
cat("\n==================== 3. 線性回歸分析 ====================\n")

# 檢驗假設1.a：傳球網絡密度對團隊得分的直接影響
cat("\n假設1.a：籃球比賽中，傳球網絡密度對團隊得分有正向影響\n")
model1a <- lm(PTS ~ density, data = merged_data)
summary_1a <- summary(model1a)
print(summary_1a)

# 檢驗假設2.a：傳球網絡中心化程度對團隊得分的直接影響
cat("\n假設2.a：籃球比賽中，傳球網絡中心化程度對團隊得分有負向影響\n")
model2a_pca <- lm(PTS ~ centralization_pca, data = merged_data)
summary_2a <- summary(model2a_pca)
print(summary_2a)

# 可視化假設2.a的結果
cat("\n繪製中心化指標與得分的關係圖...\n")
ggplot(merged_data, aes(x = centralization_pca, y = PTS)) +
  geom_point(alpha = 0.3) +
  geom_smooth(method = "lm") +
  labs(title = "PCA綜合中心化指標與團隊得分",
       x = "綜合中心化指標",
       y = "團隊得分")

# ==================== 4. 相關性分析 ====================
cat("\n==================== 4. 相關性分析 ====================\n")

# 創建包含所有相關變量的數據框
correlation_data <- data.frame(
  density = merged_data$density,
  centralization = merged_data$centralization_pca,
  assists = merged_data$AST,
  points = merged_data$PTS
)

# 移除缺失值
correlation_data <- correlation_data[complete.cases(correlation_data), ]

# 計算相關係數矩陣
cor_matrix <- cor(correlation_data)
cat("\n相關係數矩陣：\n")
print(cor_matrix)

# 計算相關係數的p值
cor_test_results <- psych::corr.test(correlation_data)
cat("\n相關係數p值矩陣：\n")
print(cor_test_results$p)

# 可視化相關係數
cat("\n繪製相關係數矩陣...\n")
corrplot(cor_matrix, 
         method = "circle", 
         type = "upper", 
         p.mat = cor_test_results$p, 
         sig.level = 0.05,
         insig = "blank")

# ==================== 5. 中介效應分析 ====================
cat("\n==================== 5. 中介效應分析 ====================\n")

# 函數：執行基於相關係數的中介效應分析並返回結果
run_correlation_mediation <- function(X, M, Y, cor_matrix, p_matrix, hypothesis_name, hypothesis_label) {
  cat(paste0("\n==================== ", hypothesis_name, " ====================\n"))
  cat(paste0("檢驗", hypothesis_label, "\n\n"))
  
  # 提取相關係數
  r_XY <- cor_matrix[X, Y]  # 總效應 (c路徑)
  r_XM <- cor_matrix[X, M]  # a路徑
  r_MY <- cor_matrix[M, Y]  # b路徑的一部分
  r_MX <- cor_matrix[M, X]  # 與a路徑相同
  
  # 計算直接效應 (c'路徑)
  # 使用偏相關公式: r_XY.M = (r_XY - r_XM*r_MY)/sqrt((1-r_XM^2)*(1-r_MY^2))
  c_prime <- (r_XY - r_XM * r_MY) / sqrt((1 - r_XM^2) * (1 - r_MY^2))
  
  # 計算間接效應 (a*b)
  indirect_effect <- r_XM * r_MY
  
  # 提取p值
  p_XY <- p_matrix[X, Y]
  p_XM <- p_matrix[X, M]
  p_MY <- p_matrix[M, Y]
  
  # 計算c'路徑的p值 (使用Fisher's z轉換估計偏相關的p值)
  n <- nrow(correlation_data)
  z_c_prime <- 0.5 * log((1 + c_prime) / (1 - c_prime))
  SE_z <- 1 / sqrt(n - 3 - 1)  # 減1是因為我們控制了一個變量
  p_c_prime <- 2 * (1 - pnorm(abs(z_c_prime) / SE_z))
  
  # Sobel檢驗 (使用相關係數)
  # 計算標準誤
  SE_a <- sqrt((1 - r_XM^2) / (n - 2))
  SE_b <- sqrt((1 - r_MY^2) / (n - 2))
  sobel_se <- sqrt((r_MY^2 * SE_a^2) + (r_XM^2 * SE_b^2))
  sobel_z <- (r_XM * r_MY) / sobel_se
  sobel_p <- 2 * (1 - pnorm(abs(sobel_z)))
  
  # 顯著性標記
  c_sig <- ifelse(p_XY < 0.001, "***", 
                  ifelse(p_XY < 0.01, "**", 
                         ifelse(p_XY < 0.05, "*", "")))
  
  a_sig <- ifelse(p_XM < 0.001, "***", 
                  ifelse(p_XM < 0.01, "**", 
                         ifelse(p_XM < 0.05, "*", "")))
  
  b_sig <- ifelse(p_MY < 0.001, "***", 
                  ifelse(p_MY < 0.01, "**", 
                         ifelse(p_MY < 0.05, "*", "")))
  
  c_prime_sig <- ifelse(p_c_prime < 0.001, "***", 
                        ifelse(p_c_prime < 0.01, "**", 
                               ifelse(p_c_prime < 0.05, "*", "")))
  
  # 中介效應類型
  mediation_type <- ifelse(sobel_p < 0.05, 
                           ifelse(p_c_prime >= 0.05, 
                                  "Complete Mediation", "Partial Mediation"), 
                           "No Mediation")
  
  # 輸出結果
  cat("Correlation-based Path Analysis Results:\n")
  cat("a path (X → M): r =", round(r_XM, 3), a_sig, "\n")
  cat("b path (M → Y): r =", round(r_MY, 3), b_sig, "\n")
  cat("c path (Total Effect): r =", round(r_XY, 3), c_sig, "\n")
  cat("c' path (Direct Effect): partial r =", round(c_prime, 3), c_prime_sig, "\n")
  cat("Indirect Effect (a×b):", round(indirect_effect, 3), "\n")
  cat("Sobel Test p-value:", format(sobel_p, digits = 3), "\n")
  cat("Mediation Type:", mediation_type, "\n\n")
  
  # 返回結果以便繪圖
  return(list(
    a = r_XM,
    b = r_MY,
    c = r_XY,
    c_prime = c_prime,
    a_sig = a_sig,
    b_sig = b_sig,
    c_sig = c_sig,
    c_prime_sig = c_prime_sig,
    indirect = indirect_effect,
    sobel_p = sobel_p,  # 添加這一行
    mediation_type = mediation_type
  ))
}

# 執行基於相關係數的中介效應分析
H1_results <- run_correlation_mediation("density", "assists", "points", 
                                        cor_matrix, cor_test_results$p,
                                        "假設1.b：密度透過助攻影響得分",
                                        "假設1.b：籃球比賽中，傳球網絡密度會透過助攻對團隊得分有正向影響")

H2_results <- run_correlation_mediation("centralization", "assists", "points", 
                                        cor_matrix, cor_test_results$p,
                                        "假設2.b：中心化透過助攻影響得分",
                                        "假設2.b：籃球比賽中，傳球網絡中心化程度會透過助攻對團隊得分有負向影響")

# ==================== 6. 繪製中介效應模型 ====================
cat("\n==================== 6. 繪製中介效應模型 ====================\n")

# 改進的中介效應繪圖函數
create_improved_mediation_plot <- function(results, x_name, m_name, y_name, title, hypothesis_label) {
  # 設置畫布
  p <- ggplot() + theme_void() + 
    labs(title = title,
         subtitle = hypothesis_label) +
    theme(plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
          plot.subtitle = element_text(hjust = 0.5, size = 12))
  
  # 節點位置
  nodes <- data.frame(
    name = c(x_name, m_name, y_name),
    x = c(1, 3, 5),
    y = c(2, 4, 2)
  )
  
  # 添加節點（方框）
  p <- p + geom_rect(data = nodes, 
                     aes(xmin = x - 0.7, xmax = x + 0.7, 
                         ymin = y - 0.5, ymax = y + 0.5),
                     fill = "white", color = "black", size = 0.5)
  
  # 添加節點標籤
  p <- p + geom_text(data = nodes, aes(x = x, y = y, label = name), size = 5)
  
  # 添加路徑和標籤
  # a路徑 (X → M)
  a_value <- round(results$a, 3)
  a_label <- paste0("a = ", a_value, results$a_sig)
  p <- p + geom_segment(aes(x = 1.7, y = 2.7, xend = 2.3, yend = 3.3), 
                        arrow = arrow(length = unit(0.3, "cm")), size = 1) +
    geom_text(aes(x = 1.5, y = 3.3, label = a_label), size = 4)
  
  # b路徑 (M → Y)
  b_value <- round(results$b, 3)
  b_label <- paste0("b = ", b_value, results$b_sig)
  p <- p + geom_segment(aes(x = 3.7, y = 3.3, xend = 4.3, yend = 2.7), 
                        arrow = arrow(length = unit(0.3, "cm")), size = 1) +
    geom_text(aes(x = 4.5, y = 3.3, label = b_label), size = 4)
  
  # c'路徑 (X → Y)
  c_prime_value <- round(results$c_prime, 3)
  c_prime_label <- paste0("c' = ", c_prime_value, results$c_prime_sig)
  p <- p + geom_segment(aes(x = 1.7, y = 2, xend = 4.3, yend = 2), 
                        arrow = arrow(length = unit(0.3, "cm")), size = 1) +
    geom_text(aes(x = 3, y = 1.7, label = c_prime_label), size = 4)
  
  # 添加間接效應 (a*b)
  indirect_value <- round(results$indirect, 3)
  indirect_sig <- ifelse(results$mediation_type != "No Mediation", "***", "")
  p <- p + geom_text(aes(x = 3, y = 4.7, 
                         label = paste0("a*b = ", indirect_value, indirect_sig)), 
                     size = 4, fontface = "bold")
  
  # 添加總效應 (c)
  c_value <- round(results$c, 3)
  p <- p + geom_text(aes(x = 3, y = 0.8, 
                         label = paste0("c = ", c_value, results$c_sig)), 
                     size = 4, fontface = "bold")
  
  # 添加中介效應類型
  p <- p + geom_text(aes(x = 3, y = 0.3, 
                         label = results$mediation_type), 
                     size = 4)
  
  # 設置適當的繪圖區域
  p <- p + coord_cartesian(xlim = c(0, 6), ylim = c(0, 5))
  
  return(p)
}

# 繪製兩個模型（分開產出）
p1 <- create_improved_mediation_plot(
  H1_results, "Density", "Assists", "Points", 
  "Mediation Analysis: Density → Assists → Points",
  ""
)

p2 <- create_improved_mediation_plot(
  H2_results, "Centralization", "Assists", "Points", 
  "Mediation Analysis: Centralization → Assists → Points",
  ""
)

# 顯示每個圖
cat("\n繪製假設1.b的中介效應模型...\n")
print(p1)

cat("\n繪製假設2.b的中介效應模型...\n")
print(p2)




# ==================== 8. 連通性指標計算 ====================
cat("\n==================== 8. 連通性指標計算 ====================\n")

# 選擇連通性相關的變數
connectivity_vars <- c("vertex_connectivity", "edge_connectivity")

# 檢查這些變數是否在資料集中
available_connectivity_vars <- intersect(connectivity_vars, names(merged_data))
cat("可用的連通性指標（", length(available_connectivity_vars), "個）：\n")
cat(paste(available_connectivity_vars, collapse = ", "), "\n\n")

# 使用可用的連通性變數
connectivity_data <- merged_data[, available_connectivity_vars]

# 檢查是否有缺失值
missing_count <- sum(is.na(connectivity_data))
cat("連通性指標缺失值數量：", missing_count, "\n")

# 處理缺失值
connectivity_data <- na.omit(connectivity_data)

# 如果有兩個以上的連通性指標，進行主成分分析
if(length(available_connectivity_vars) >= 2) {
  # 進行主成分分析
  pca_connectivity <- prcomp(connectivity_data, 
                             center = TRUE,  # 標準化
                             scale. = TRUE)  # 使用標準差縮放
  
  # 查看主成分解釋的方差比例
  pca_conn_summary <- summary(pca_connectivity)
  cat("\n連通性主成分分析結果：\n")
  print(pca_conn_summary$importance)
  
  # 可視化方差解釋
  cat("\n繪製連通性主成分方差解釋圖...\n")
  fviz_eig(pca_connectivity)
  
  # 提取第一主成分作為綜合連通性指標
  merged_data$connectivity_pca <- pca_connectivity$x[, -1]
  
  # 檢查新的連通性指標與原始指標的相關性
  cor_with_conn_pca <- cor(merged_data[, available_connectivity_vars], 
                           merged_data$connectivity_pca, 
                           use = "complete.obs")
  cat("\n連通性指標與PCA第一主成分的相關性：\n")
  print(cor_with_conn_pca)
  
  # 查看主成分的載荷矩陣
  cat("\n連通性主成分載荷矩陣：\n")
  print(pca_connectivity$rotation)
  
  # 可視化連通性指標間的相關性
  cat("\n繪製連通性指標相關性矩陣...\n")
  corrplot(cor(merged_data[, available_connectivity_vars], use = "complete.obs"), 
           method = "circle", 
           type = "upper")
} else if(length(available_connectivity_vars) == 1) {
  # 如果只有一個連通性指標，直接使用它
  cat("\n只有一個連通性指標可用，直接使用：", available_connectivity_vars, "\n")
  merged_data$connectivity_pca <- merged_data[, available_connectivity_vars]
} else {
  # 如果沒有連通性指標可用
  cat("\n警告：沒有可用的連通性指標！\n")
}

merged_data$connectivity_pca <- merged_data$vertex_connectivity

# ==================== 9. 檢查社群模組化指標 ====================
cat("\n==================== 9. 檢查社群模組化指標 ====================\n")

# 檢查best_modularity是否在資料集中
if("best_modularity" %in% names(merged_data)) {
  cat("社群模組化指標 'best_modularity' 可用\n")
  
  # 檢查缺失值
  missing_mod <- sum(is.na(merged_data$best_modularity))
  cat("社群模組化指標缺失值數量：", missing_mod, "\n")
} else {
  cat("警告：社群模組化指標 'best_modularity' 不可用！\n")
  
  # 檢查其他可能的模組化指標
  possible_mod_vars <- c("walktrap_modularity", "louvain_modularity")
  available_mod_vars <- intersect(possible_mod_vars, names(merged_data))
  
  if(length(available_mod_vars) > 0) {
    cat("可用的替代模組化指標：", paste(available_mod_vars, collapse = ", "), "\n")
    
    # 使用第一個可用的模組化指標作為替代
    merged_data$best_modularity <- merged_data[, available_mod_vars[1]]
    cat("使用 '", available_mod_vars[1], "' 作為社群模組化指標\n")
  } else {
    cat("錯誤：沒有可用的模組化指標！\n")
  }
}

# ==================== 10. 線性回歸分析（假設3.a和4.a）====================
cat("\n==================== 10. 線性回歸分析（假設3.a和4.a）====================\n")

# 檢驗假設3.a：傳球網絡連通性對團隊得分的直接影響
cat("\n假設3.a：籃球比賽中，傳球網絡連通性對團隊得分有正向影響\n")
if(exists("connectivity_pca", where = merged_data)) {
  model3a <- lm(PTS ~ connectivity_pca, data = merged_data)
  summary_3a <- summary(model3a)
  print(summary_3a)
  
  # 可視化假設3.a的結果
  cat("\n繪製連通性指標與得分的關係圖...\n")
  ggplot(merged_data, aes(x = connectivity_pca, y = PTS)) +
    geom_point(alpha = 0.3) +
    geom_smooth(method = "lm") +
    labs(title = "連通性指標與團隊得分",
         x = "連通性指標",
         y = "團隊得分")
} else {
  cat("錯誤：無法檢驗假設3.a，連通性指標不可用\n")
}

# 檢驗假設4.a：傳球網絡社群模組化程度對團隊得分的直接影響
cat("\n假設4.a：籃球比賽中，傳球網絡社群模組化程度對團隊得分有負向影響\n")
if("best_modularity" %in% names(merged_data)) {
  model4a <- lm(PTS ~ best_modularity, data = merged_data)
  summary_4a <- summary(model4a)
  print(summary_4a)
  
  # 可視化假設4.a的結果
  cat("\n繪製社群模組化指標與得分的關係圖...\n")
  ggplot(merged_data, aes(x = best_modularity, y = PTS)) +
    geom_point(alpha = 0.3) +
    geom_smooth(method = "lm") +
    labs(title = "社群模組化指標與團隊得分",
         x = "社群模組化指標",
         y = "團隊得分")
} else {
  cat("錯誤：無法檢驗假設4.a，社群模組化指標不可用\n")
}

# ==================== 11. 更新相關性分析 ====================
cat("\n==================== 11. 更新相關性分析 ====================\n")

# 創建包含所有相關變量的數據框
correlation_data_extended <- data.frame(
  density = merged_data$density,
  centralization = merged_data$centralization_pca,
  assists = merged_data$AST,
  points = merged_data$PTS
)

# 添加連通性和模組化指標（如果可用）
if(exists("connectivity_pca", where = merged_data)) {
  correlation_data_extended$connectivity <- merged_data$connectivity_pca
}

if("louvain_modularity" %in% names(merged_data)) {
  correlation_data_extended$modularity <- merged_data$louvain_modularity
}

# 移除缺失值
correlation_data_extended <- correlation_data_extended[complete.cases(correlation_data_extended), ]

# 計算相關係數矩陣
cor_matrix_extended <- cor(correlation_data_extended)
cat("\n擴展相關係數矩陣：\n")
print(cor_matrix_extended)

# 計算相關係數的p值
cor_test_results_extended <- psych::corr.test(correlation_data_extended)
cat("\n擴展相關係數p值矩陣：\n")
print(cor_test_results_extended$p)

# 可視化相關係數
cat("\n繪製擴展相關係數矩陣...\n")
corrplot(cor_matrix_extended, 
         method = "circle", 
         type = "upper", 
         p.mat = cor_test_results_extended$p, 
         sig.level = 0.05,
         insig = "blank")

# ==================== 12. 中介效應分析（假設3.b和4.b）====================
cat("\n==================== 12. 中介效應分析（假設3.b和4.b）====================\n")

# 執行基於相關係數的中介效應分析（假設3.b）
if("connectivity" %in% names(correlation_data_extended)) {
  H3_results <- run_correlation_mediation("connectivity", "assists", "points", 
                                          cor_matrix_extended, cor_test_results_extended$p,
                                          "假設3.b：連通性透過助攻影響得分",
                                          "假設3.b：籃球比賽中，傳球網絡連通性會透過助攻對團隊得分有正向影響")
} else {
  cat("錯誤：無法檢驗假設3.b，連通性指標不可用\n")
}

# 執行基於相關係數的中介效應分析（假設4.b）
if("modularity" %in% names(correlation_data_extended)) {
  H4_results <- run_correlation_mediation("modularity", "assists", "points", 
                                          cor_matrix_extended, cor_test_results_extended$p,
                                          "假設4.b：模組化透過助攻影響得分",
                                          "假設4.b：籃球比賽中，傳球網絡社群模組化程度會透過助攻對團隊得分有負向影響")
} else {
  cat("錯誤：無法檢驗假設4.b，社群模組化指標不可用\n")
}

# ==================== 13. 繪製中介效應模型（假設3.b和4.b）====================
cat("\n==================== 13. 繪製中介效應模型（假設3.b和4.b）====================\n")

# 繪製假設3.b的中介效應模型
if(exists("H3_results")) {
  p3 <- create_improved_mediation_plot(
    H3_results, "Connectivity", "Assists", "Points", 
    "Mediation Analysis: Connectivity → Assists → Points",
    ""
  )
  
  cat("\n繪製假設3.b的中介效應模型...\n")
  print(p3)
}

# 繪製假設4.b的中介效應模型
if(exists("H4_results")) {
  p4 <- create_improved_mediation_plot(
    H4_results, "Modularity", "Assists", "Points", 
    "Mediation Analysis: Modularity → Assists → Points",
    ""
  )
  
  cat("\n繪製假設4.b的中介效應模型...\n")
  print(p4)
}















# 選擇分析用的表現指標
performance_vars <- c("PTS", "AST", "REB", "FG_PCT", 
                      "STL", "BLK", "TO", "POSS")

# ==================== 16. 控制變數後的相關性分析 ====================
cat("\n==================== 16. 控制變數後的相關性分析 ====================\n")

# 定義要控制的變數
control_vars <- c("REB", "FG_PCT", "STL", "POSS")

# 檢查控制變數是否都在資料集中
available_control_vars <- intersect(control_vars, names(merged_data))
cat("可用的控制變數（", length(available_control_vars), "個）：\n")
cat(paste(available_control_vars, collapse = ", "), "\n\n")

# 創建包含所有相關變量的數據框（包括控制變數）
correlation_data_with_controls <- data.frame(
  density = merged_data$density,
  centralization = merged_data$centralization_pca,
  assists = merged_data$AST,
  points = merged_data$PTS
)

# 添加連通性和模組化指標（如果可用）
if(exists("connectivity_pca", where = merged_data)) {
  correlation_data_with_controls$connectivity <- merged_data$connectivity_pca
}

if("best_modularity" %in% names(merged_data)) {
  correlation_data_with_controls$modularity <- merged_data$best_modularity
}

# 添加控制變數
for(var in available_control_vars) {
  correlation_data_with_controls[[var]] <- merged_data[[var]]
}

# 移除缺失值
correlation_data_with_controls <- correlation_data_with_controls[complete.cases(correlation_data_with_controls), ]

# 函數：計算偏相關係數
calculate_partial_correlation <- function(data, x_var, y_var, control_vars) {
  # 構建公式
  formula_x <- as.formula(paste(x_var, "~", paste(control_vars, collapse = "+")))
  formula_y <- as.formula(paste(y_var, "~", paste(control_vars, collapse = "+")))
  
  # 計算殘差
  residuals_x <- residuals(lm(formula_x, data = data))
  residuals_y <- residuals(lm(formula_y, data = data))
  
  # 計算殘差間的相關係數（即偏相關係數）
  partial_cor <- cor(residuals_x, residuals_y)
  
  # 計算p值
  n <- length(residuals_x)
  df <- n - 2 - length(control_vars)
  t_value <- partial_cor * sqrt(df) / sqrt(1 - partial_cor^2)
  p_value <- 2 * pt(abs(t_value), df, lower.tail = FALSE)
  
  return(list(cor = partial_cor, p = p_value))
}

# 計算網絡指標與得分的偏相關係數（控制其他表現指標）
cat("\n控制", paste(available_control_vars, collapse = ", "), "後的偏相關係數：\n")

# 密度與得分
density_pts_partial <- calculate_partial_correlation(correlation_data_with_controls, 
                                                     "density", "points", 
                                                     available_control_vars)
cat("密度與得分的偏相關係數：", round(density_pts_partial$cor, 3), 
    "，p值：", format(density_pts_partial$p, digits = 3), "\n")

# 中心化與得分
centralization_pts_partial <- calculate_partial_correlation(correlation_data_with_controls, 
                                                            "centralization", "points", 
                                                            available_control_vars)
cat("中心化與得分的偏相關係數：", round(centralization_pts_partial$cor, 3), 
    "，p值：", format(centralization_pts_partial$p, digits = 3), "\n")

# 連通性與得分（如果可用）
if("connectivity" %in% names(correlation_data_with_controls)) {
  connectivity_pts_partial <- calculate_partial_correlation(correlation_data_with_controls, 
                                                            "connectivity", "points", 
                                                            available_control_vars)
  cat("連通性與得分的偏相關係數：", round(connectivity_pts_partial$cor, 3), 
      "，p值：", format(connectivity_pts_partial$p, digits = 3), "\n")
}

# 模組化與得分（如果可用）
if("modularity" %in% names(correlation_data_with_controls)) {
  modularity_pts_partial <- calculate_partial_correlation(correlation_data_with_controls, 
                                                          "modularity", "points", 
                                                          available_control_vars)
  cat("模組化與得分的偏相關係數：", round(modularity_pts_partial$cor, 3), 
      "，p值：", format(modularity_pts_partial$p, digits = 3), "\n")
}

# 密度與助攻
density_ast_partial <- calculate_partial_correlation(correlation_data_with_controls, 
                                                     "density", "assists", 
                                                     available_control_vars)
cat("密度與助攻的偏相關係數：", round(density_ast_partial$cor, 3), 
    "，p值：", format(density_ast_partial$p, digits = 3), "\n")

# 中心化與助攻
centralization_ast_partial <- calculate_partial_correlation(correlation_data_with_controls, 
                                                            "centralization", "assists", 
                                                            available_control_vars)
cat("中心化與助攻的偏相關係數：", round(centralization_ast_partial$cor, 3), 
    "，p值：", format(centralization_ast_partial$p, digits = 3), "\n")

# 連通性與助攻（如果可用）
if("connectivity" %in% names(correlation_data_with_controls)) {
  connectivity_ast_partial <- calculate_partial_correlation(correlation_data_with_controls, 
                                                            "connectivity", "assists", 
                                                            available_control_vars)
  cat("連通性與助攻的偏相關係數：", round(connectivity_ast_partial$cor, 3), 
      "，p值：", format(connectivity_ast_partial$p, digits = 3), "\n")
}

# 模組化與助攻（如果可用）
if("modularity" %in% names(correlation_data_with_controls)) {
  modularity_ast_partial <- calculate_partial_correlation(correlation_data_with_controls, 
                                                          "modularity", "assists", 
                                                          available_control_vars)
  cat("模組化與助攻的偏相關係數：", round(modularity_ast_partial$cor, 3), 
      "，p值：", format(modularity_ast_partial$p, digits = 3), "\n")
}

# 助攻與得分
ast_pts_partial <- calculate_partial_correlation(correlation_data_with_controls, 
                                                 "assists", "points", 
                                                 available_control_vars)
cat("助攻與得分的偏相關係數：", round(ast_pts_partial$cor, 3), 
    "，p值：", format(ast_pts_partial$p, digits = 3), "\n")

# ==================== 17. 控制變數後的中介效應分析 ====================
cat("\n==================== 17. 控制變數後的中介效應分析 ====================\n")

# 函數：執行基於偏相關係數的中介效應分析
run_partial_correlation_mediation <- function(data, X, M, Y, control_vars, hypothesis_name, hypothesis_label) {
  cat(paste0("\n==================== ", hypothesis_name, " ====================\n"))
  cat(paste0("檢驗", hypothesis_label, "（控制", paste(control_vars, collapse = ", "), "）\n\n"))
  
  # 計算偏相關係數
  r_XY_partial <- calculate_partial_correlation(data, X, Y, control_vars)
  r_XM_partial <- calculate_partial_correlation(data, X, M, control_vars)
  r_MY_partial <- calculate_partial_correlation(data, M, Y, control_vars)
  
  # 提取相關係數和p值
  r_XY <- r_XY_partial$cor
  p_XY <- r_XY_partial$p
  r_XM <- r_XM_partial$cor
  p_XM <- r_XM_partial$p
  r_MY <- r_MY_partial$cor
  p_MY <- r_MY_partial$p
  
  # 計算直接效應 (c'路徑)
  # 構建包含中介變量和控制變量的公式
  control_formula <- paste(c(M, control_vars), collapse = "+")
  formula_direct <- as.formula(paste(Y, "~", X, "+", control_formula))
  
  # 擬合模型
  model_direct <- lm(formula_direct, data = data)
  summary_direct <- summary(model_direct)
  
  # 提取直接效應係數和p值
  c_prime <- summary_direct$coefficients[X, "Estimate"]
  p_c_prime <- summary_direct$coefficients[X, "Pr(>|t|)"]
  
  # 計算間接效應 (a*b)
  indirect_effect <- r_XM * r_MY
  
  # Sobel檢驗
  n <- nrow(data)
  SE_a <- sqrt((1 - r_XM^2) / (n - length(control_vars) - 2))
  SE_b <- sqrt((1 - r_MY^2) / (n - length(control_vars) - 2))
  sobel_se <- sqrt((r_MY^2 * SE_a^2) + (r_XM^2 * SE_b^2))
  sobel_z <- (r_XM * r_MY) / sobel_se
  sobel_p <- 2 * (1 - pnorm(abs(sobel_z)))
  
  # 顯著性標記
  c_sig <- ifelse(p_XY < 0.001, "***", 
                  ifelse(p_XY < 0.01, "**", 
                         ifelse(p_XY < 0.05, "*", "")))
  
  a_sig <- ifelse(p_XM < 0.001, "***", 
                  ifelse(p_XM < 0.01, "**", 
                         ifelse(p_XM < 0.05, "*", "")))
  
  b_sig <- ifelse(p_MY < 0.001, "***", 
                  ifelse(p_MY < 0.01, "**", 
                         ifelse(p_MY < 0.05, "*", "")))
  
  c_prime_sig <- ifelse(p_c_prime < 0.001, "***", 
                        ifelse(p_c_prime < 0.01, "**", 
                               ifelse(p_c_prime < 0.05, "*", "")))
  
  # 中介效應類型
  mediation_type <- ifelse(sobel_p < 0.05, 
                           ifelse(p_c_prime >= 0.05, 
                                  "Complete Mediation", "Partial Mediation"), 
                           "No Mediation")
  
  # 輸出結果
  cat("Partial Correlation-based Path Analysis Results:\n")
  cat("a path (X → M): partial r =", round(r_XM, 3), a_sig, "\n")
  cat("b path (M → Y): partial r =", round(r_MY, 3), b_sig, "\n")
  cat("c path (Total Effect): partial r =", round(r_XY, 3), c_sig, "\n")
  cat("c' path (Direct Effect): coefficient =", round(c_prime, 3), c_prime_sig, "\n")
  cat("Indirect Effect (a×b):", round(indirect_effect, 3), "\n")
  cat("Sobel Test p-value:", format(sobel_p, digits = 3), "\n")
  cat("Mediation Type:", mediation_type, "\n\n")
  
  # 返回結果以便繪圖
  return(list(
    a = r_XM,
    b = r_MY,
    c = r_XY,
    c_prime = c_prime,
    a_sig = a_sig,
    b_sig = b_sig,
    c_sig = c_sig,
    c_prime_sig = c_prime_sig,
    indirect = indirect_effect,
    sobel_p = sobel_p,
    mediation_type = mediation_type
  ))
}

# 執行基於偏相關係數的中介效應分析（假設1.b - 控制變數）
H1_results_controlled <- run_partial_correlation_mediation(
  correlation_data_with_controls, "density", "assists", "points", 
  available_control_vars,
  "假設1.b（控制變數）：密度透過助攻影響得分",
  "假設1.b：籃球比賽中，傳球網絡密度會透過助攻對團隊得分有正向影響"
)

# 執行基於偏相關係數的中介效應分析（假設2.b - 控制變數）
H2_results_controlled <- run_partial_correlation_mediation(
  correlation_data_with_controls, "centralization", "assists", "points", 
  available_control_vars,
  "假設2.b（控制變數）：中心化透過助攻影響得分",
  "假設2.b：籃球比賽中，傳球網絡中心化程度會透過助攻對團隊得分有負向影響"
)

# 執行基於偏相關係數的中介效應分析（假設3.b - 控制變數）
if("connectivity" %in% names(correlation_data_with_controls)) {
  H3_results_controlled <- run_partial_correlation_mediation(
    correlation_data_with_controls, "connectivity", "assists", "points", 
    available_control_vars,
    "假設3.b（控制變數）：連通性透過助攻影響得分",
    "假設3.b：籃球比賽中，傳球網絡連通性會透過助攻對團隊得分有正向影響"
  )
}

# 執行基於偏相關係數的中介效應分析（假設4.b - 控制變數）
if("modularity" %in% names(correlation_data_with_controls)) {
  H4_results_controlled <- run_partial_correlation_mediation(
    correlation_data_with_controls, "modularity", "assists", "points", 
    available_control_vars,
    "假設4.b（控制變數）：模組化透過助攻影響得分",
    "假設4.b：籃球比賽中，傳球網絡社群模組化程度會透過助攻對團隊得分有負向影響"
  )
}

# ==================== 18. 繪製控制變數後的中介效應模型 ====================
cat("\n==================== 18. 繪製控制變數後的中介效應模型 ====================\n")

# 繪製假設1.b的中介效應模型（控制變數後）
p1_controlled <- create_improved_mediation_plot(
  H1_results_controlled, "Density", "Assists", "Points", 
  "Mediation Analysis (Controlled): Density → Assists → Points",
  paste0("假設1.b（控制", paste(available_control_vars, collapse = ", "), "）")
)

cat("\n繪製假設1.b的中介效應模型（控制變數後）...\n")
print(p1_controlled)

# 繪製假設2.b的中介效應模型（控制變數後）
p2_controlled <- create_improved_mediation_plot(
  H2_results_controlled, "Centralization", "Assists", "Points", 
  "Mediation Analysis (Controlled): Centralization → Assists → Points",
  paste0("假設2.b（控制", paste(available_control_vars, collapse = ", "), "）")
)

cat("\n繪製假設2.b的中介效應模型（控制變數後）...\n")
print(p2_controlled)

# 繪製假設3.b的中介效應模型（控制變數後）
if(exists("H3_results_controlled")) {
  p3_controlled <- create_improved_mediation_plot(
    H3_results_controlled, "Connectivity", "Assists", "Points", 
    "Mediation Analysis (Controlled): Connectivity → Assists → Points",
    paste0("假設3.b（控制", paste(available_control_vars, collapse = ", "), "）")
  )
  
  cat("\n繪製假設3.b的中介效應模型（控制變數後）...\n")
  print(p3_controlled)
}

# 繪製假設4.b的中介效應模型（控制變數後）
if(exists("H4_results_controlled")) {
  p4_controlled <- create_improved_mediation_plot(
    H4_results_controlled, "Modularity", "Assists", "Points", 
    "Mediation Analysis (Controlled): Modularity → Assists → Points",
    paste0("假設4.b（控制", paste(available_control_vars, collapse = ", "), "）")
  )
  
  cat("\n繪製假設4.b的中介效應模型（控制變數後）...\n")
  print(p4_controlled)
}





# ==================== 20. 彙整控制前後假設檢驗路徑係數比較表 ====================
cat("\n==================== 20. 彙整控制前後假設檢驗路徑係數比較表 ====================\n")

# 載入必要的套件
if (!require(knitr)) install.packages("knitr")
if (!require(kableExtra)) install.packages("kableExtra")
library(knitr)
library(kableExtra)

# 創建一個函數來格式化係數和顯著性標記
format_coef_sig <- function(coef, sig) {
  return(paste0(sprintf("%.3f", round(coef, 3)), sig))
}

# 建立路徑係數比較表的數據框
path_coefficients <- data.frame(
  假設 = character(),
  a路徑控制前 = character(),
  a路徑控制後 = character(),
  b路徑控制前 = character(),
  b路徑控制後 = character(),
  c直接效應控制前 = character(),
  c直接效應控制後 = character(),
  stringsAsFactors = FALSE
)

# 假設1.b
if(exists("H1_results") && exists("H1_results_controlled")) {
  path_coefficients <- rbind(path_coefficients, data.frame(
    假設 = "1.b: 密度→助攻→得分",
    a路徑控制前 = format_coef_sig(H1_results$a, H1_results$a_sig),
    a路徑控制後 = format_coef_sig(H1_results_controlled$a, H1_results_controlled$a_sig),
    b路徑控制前 = format_coef_sig(H1_results$b, H1_results$b_sig),
    b路徑控制後 = format_coef_sig(H1_results_controlled$b, H1_results_controlled$b_sig),
    c直接效應控制前 = format_coef_sig(H1_results$c_prime, H1_results$c_prime_sig),
    c直接效應控制後 = format_coef_sig(H1_results_controlled$c_prime, H1_results_controlled$c_prime_sig),
    stringsAsFactors = FALSE
  ))
}

# 假設2.b
if(exists("H2_results") && exists("H2_results_controlled")) {
  path_coefficients <- rbind(path_coefficients, data.frame(
    假設 = "2.b: 中心化→助攻→得分",
    a路徑控制前 = format_coef_sig(H2_results$a, H2_results$a_sig),
    a路徑控制後 = format_coef_sig(H2_results_controlled$a, H2_results_controlled$a_sig),
    b路徑控制前 = format_coef_sig(H2_results$b, H2_results$b_sig),
    b路徑控制後 = format_coef_sig(H2_results_controlled$b, H2_results_controlled$b_sig),
    c直接效應控制前 = format_coef_sig(H2_results$c_prime, H2_results$c_prime_sig),
    c直接效應控制後 = format_coef_sig(H2_results_controlled$c_prime, H2_results_controlled$c_prime_sig),
    stringsAsFactors = FALSE
  ))
}

# 假設3.b
if(exists("H3_results") && exists("H3_results_controlled")) {
  path_coefficients <- rbind(path_coefficients, data.frame(
    假設 = "3.b: 連通性→助攻→得分",
    a路徑控制前 = format_coef_sig(H3_results$a, H3_results$a_sig),
    a路徑控制後 = format_coef_sig(H3_results_controlled$a, H3_results_controlled$a_sig),
    b路徑控制前 = format_coef_sig(H3_results$b, H3_results$b_sig),
    b路徑控制後 = format_coef_sig(H3_results_controlled$b, H3_results_controlled$b_sig),
    c直接效應控制前 = format_coef_sig(H3_results$c_prime, H3_results$c_prime_sig),
    c直接效應控制後 = format_coef_sig(H3_results_controlled$c_prime, H3_results_controlled$c_prime_sig),
    stringsAsFactors = FALSE
  ))
}

# 假設4.b
if(exists("H4_results") && exists("H4_results_controlled")) {
  path_coefficients <- rbind(path_coefficients, data.frame(
    假設 = "4.b: 模組化→助攻→得分",
    a路徑控制前 = format_coef_sig(H4_results$a, H4_results$a_sig),
    a路徑控制後 = format_coef_sig(H4_results_controlled$a, H4_results_controlled$a_sig),
    b路徑控制前 = format_coef_sig(H4_results$b, H4_results$b_sig),
    b路徑控制後 = format_coef_sig(H4_results_controlled$b, H4_results_controlled$b_sig),
    c直接效應控制前 = format_coef_sig(H4_results$c_prime, H4_results$c_prime_sig),
    c直接效應控制後 = format_coef_sig(H4_results_controlled$c_prime, H4_results_controlled$c_prime_sig),
    stringsAsFactors = FALSE
  ))
}

# 使用kable創建表格
cat("\n各假設路徑係數比較表（控制前 vs 控制後）：\n")
path_table <- kable(path_coefficients, format = "markdown", 
                    caption = "各假設路徑係數比較表（控制前 vs 控制後）")
print(path_table)

# 建立總效應和間接效應比較表的數據框
effects_table <- data.frame(
  假設 = character(),
  總效應控制前 = character(),
  總效應控制後 = character(),
  間接效應控制前 = character(),
  間接效應控制後 = character(),
  中介類型控制前 = character(),
  中介類型控制後 = character(),
  stringsAsFactors = FALSE
)

# 假設1.b
if(exists("H1_results") && exists("H1_results_controlled")) {
  effects_table <- rbind(effects_table, data.frame(
    假設 = "1.b: 密度→助攻→得分",
    總效應控制前 = format_coef_sig(H1_results$c, H1_results$c_sig),
    總效應控制後 = format_coef_sig(H1_results_controlled$c, H1_results_controlled$c_sig),
    間接效應控制前 = sprintf("%.3f", round(H1_results$indirect, 3)),
    間接效應控制後 = sprintf("%.3f", round(H1_results_controlled$indirect, 3)),
    中介類型控制前 = H1_results$mediation_type,
    中介類型控制後 = H1_results_controlled$mediation_type,
    stringsAsFactors = FALSE
  ))
}

# 假設2.b
if(exists("H2_results") && exists("H2_results_controlled")) {
  effects_table <- rbind(effects_table, data.frame(
    假設 = "2.b: 中心化→助攻→得分",
    總效應控制前 = format_coef_sig(H2_results$c, H2_results$c_sig),
    總效應控制後 = format_coef_sig(H2_results_controlled$c, H2_results_controlled$c_sig),
    間接效應控制前 = sprintf("%.3f", round(H2_results$indirect, 3)),
    間接效應控制後 = sprintf("%.3f", round(H2_results_controlled$indirect, 3)),
    中介類型控制前 = H2_results$mediation_type,
    中介類型控制後 = H2_results_controlled$mediation_type,
    stringsAsFactors = FALSE
  ))
}

# 假設3.b
if(exists("H3_results") && exists("H3_results_controlled")) {
  effects_table <- rbind(effects_table, data.frame(
    假設 = "3.b: 連通性→助攻→得分",
    總效應控制前 = format_coef_sig(H3_results$c, H3_results$c_sig),
    總效應控制後 = format_coef_sig(H3_results_controlled$c, H3_results_controlled$c_sig),
    間接效應控制前 = sprintf("%.3f", round(H3_results$indirect, 3)),
    間接效應控制後 = sprintf("%.3f", round(H3_results_controlled$indirect, 3)),
    中介類型控制前 = H3_results$mediation_type,
    中介類型控制後 = H3_results_controlled$mediation_type,
    stringsAsFactors = FALSE
  ))
}

# 假設4.b
if(exists("H4_results") && exists("H4_results_controlled")) {
  effects_table <- rbind(effects_table, data.frame(
    假設 = "4.b: 模組化→助攻→得分",
    總效應控制前 = format_coef_sig(H4_results$c, H4_results$c_sig),
    總效應控制後 = format_coef_sig(H4_results_controlled$c, H4_results_controlled$c_sig),
    間接效應控制前 = sprintf("%.3f", round(H4_results$indirect, 3)),
    間接效應控制後 = sprintf("%.3f", round(H4_results_controlled$indirect, 3)),
    中介類型控制前 = H4_results$mediation_type,
    中介類型控制後 = H4_results_controlled$mediation_type,
    stringsAsFactors = FALSE
  ))
}

# 使用kable創建表格
cat("\n各假設總效應和間接效應比較表（控制前 vs 控制後）：\n")
effects_kable <- kable(effects_table, format = "markdown",
                       caption = "各假設總效應和間接效應比較表（控制前 vs 控制後）")
print(effects_kable)
cat("\n註：* p<0.05, ** p<0.01, *** p<0.001\n")
cat("控制變數：", paste(available_control_vars, collapse = ", "), "\n")

# 建立研究假設檢驗結果摘要表的數據框
hypothesis_table <- data.frame(
  研究假設 = character(),
  控制前結果 = character(),
  控制後結果 = character(),
  結論 = character(),
  stringsAsFactors = FALSE
)

# 假設1.b
if(exists("H1_results") && exists("H1_results_controlled")) {
  result1b <- ifelse(H1_results$a > 0 && H1_results$b > 0 && 
                       H1_results$mediation_type != "No Mediation", "支持", "不支持")
  result1b_controlled <- ifelse(H1_results_controlled$a > 0 && H1_results_controlled$b > 0 && 
                                  H1_results_controlled$mediation_type != "No Mediation", "支持", "不支持")
  conclusion1b <- ifelse(result1b == "支持" && result1b_controlled == "支持", 
                         "假設獲得強力支持",
                         ifelse(result1b == "支持" || result1b_controlled == "支持",
                                "假設獲得部分支持", "假設未獲支持"))
  hypothesis_table <- rbind(hypothesis_table, data.frame(
    研究假設 = "H1.b: 傳球網絡密度會透過助攻對團隊得分有正向影響",
    控制前結果 = result1b,
    控制後結果 = result1b_controlled,
    結論 = conclusion1b,
    stringsAsFactors = FALSE
  ))
}

# 假設2.b
if(exists("H2_results") && exists("H2_results_controlled")) {
  result2b <- ifelse(H2_results$a < 0 && H2_results$b > 0 && 
                       H2_results$mediation_type != "No Mediation", "支持", "不支持")
  result2b_controlled <- ifelse(H2_results_controlled$a < 0 && H2_results_controlled$b > 0 && 
                                  H2_results_controlled$mediation_type != "No Mediation", "支持", "不支持")
  conclusion2b <- ifelse(result2b == "支持" && result2b_controlled == "支持", 
                         "假設獲得強力支持",
                         ifelse(result2b == "支持" || result2b_controlled == "支持",
                                "假設獲得部分支持", "假設未獲支持"))
  hypothesis_table <- rbind(hypothesis_table, data.frame(
    研究假設 = "H2.b: 傳球網絡中心化程度會透過助攻對團隊得分有負向影響",
    控制前結果 = result2b,
    控制後結果 = result2b_controlled,
    結論 = conclusion2b,
    stringsAsFactors = FALSE
  ))
}

# 假設3.b
if(exists("H3_results") && exists("H3_results_controlled")) {
  result3b <- ifelse(H3_results$a > 0 && H3_results$b > 0 && 
                       H3_results$mediation_type != "No Mediation", "支持", "不支持")
  result3b_controlled <- ifelse(H3_results_controlled$a > 0 && H3_results_controlled$b > 0 && 
                                  H3_results_controlled$mediation_type != "No Mediation", "支持", "不支持")
  conclusion3b <- ifelse(result3b == "支持" && result3b_controlled == "支持", 
                         "假設獲得強力支持",
                         ifelse(result3b == "支持" || result3b_controlled == "支持",
                                "假設獲得部分支持", "假設未獲支持"))
  hypothesis_table <- rbind(hypothesis_table, data.frame(
    研究假設 = "H3.b: 傳球網絡連通性會透過助攻對團隊得分有正向影響",
    控制前結果 = result3b,
    控制後結果 = result3b_controlled,
    結論 = conclusion3b,
    stringsAsFactors = FALSE
  ))
}

# 假設4.b
if(exists("H4_results") && exists("H4_results_controlled")) {
  result4b <- ifelse(H4_results$a < 0 && H4_results$b > 0 && 
                       H4_results$mediation_type != "No Mediation", "支持", "不支持")
  result4b_controlled <- ifelse(H4_results_controlled$a < 0 && H4_results_controlled$b > 0 && 
                                  H4_results_controlled$mediation_type != "No Mediation", "支持", "不支持")
  conclusion4b <- ifelse(result4b == "支持" && result4b_controlled == "支持", 
                         "假設獲得強力支持",
                         ifelse(result4b == "支持" || result4b_controlled == "支持",
                                "假設獲得部分支持", "假設未獲支持"))
  hypothesis_table <- rbind(hypothesis_table, data.frame(
    研究假設 = "H4.b: 傳球網絡社群模組化程度會透過助攻對團隊得分有負向影響",
    控制前結果 = result4b,
    控制後結果 = result4b_controlled,
    結論 = conclusion4b,
    stringsAsFactors = FALSE
  ))
}

# 使用kable創建表格
cat("\n研究假設檢驗結果摘要：\n")
hypothesis_kable <- kable(hypothesis_table, format = "markdown",
                          caption = "研究假設檢驗結果摘要")
print(hypothesis_kable)
cat("\n控制變數：", paste(available_control_vars, collapse = ", "), "\n")



