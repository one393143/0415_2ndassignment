# NBA傳球網絡分析系統
library(igraph)
library(scales)
library(dplyr)
library(jsonlite)
library(ggplot2)
library(lubridate)
library(readr)
library(stringr)

# 自動設定工作目錄
current_path <- rstudioapi::getActiveDocumentContext()$path
if (!is.null(current_path) && current_path != "") setwd(dirname(current_path)) else stop("無法自動檢測 R 檔案的路徑")

#' 匯入球隊表現數據
import_team_performance <- function(performance_path = "data/performance_team") {
  cat("\n正在匯入球隊表現數據...\n")
  
  if (!dir.exists(performance_path)) {
    stop("球隊表現資料夾不存在")
  }
  
  result <- list()
  
  regular_season_file <- file.path(performance_path, "nba_regular_season_stats_2015_to_2024.csv")
  if (file.exists(regular_season_file)) {
    result$regular_season_stats <- read_csv(regular_season_file, show_col_types = FALSE)
    cat("成功讀取例行賽統計數據，共", nrow(result$regular_season_stats), "筆記錄\n")
  } else {
    result$regular_season_stats <- NULL
  }
  
  playoff_file <- file.path(performance_path, "nba_playoff_stats_2015_to_2024.csv")
  if (file.exists(playoff_file)) {
    result$playoff_stats <- read_csv(playoff_file, show_col_types = FALSE)
    cat("成功讀取季後賽統計數據，共", nrow(result$playoff_stats), "筆記錄\n")
  } else {
    result$playoff_stats <- NULL
  }
  
  standings_file <- file.path(performance_path, "nba_league_standings_2015_to_2024.csv")
  if (file.exists(standings_file)) {
    result$league_standings <- read_csv(standings_file, show_col_types = FALSE)
    cat("成功讀取聯盟排名數據，共", nrow(result$league_standings), "筆記錄\n")
  } else {
    result$league_standings <- NULL
  }
  
  return(result)
}

#' 匯入球員逐場數據
import_player_game_data <- function(player_path = "data/performance_player_pergame") {
  cat("\n正在匯入球員逐場數據...\n")
  
  if (!dir.exists(player_path)) {
    stop("球員表現資料夾不存在")
  }
  
  player_files <- list.files(player_path, pattern = "\\d{4}-\\d{2}_player_game_data\\.csv", full.names = TRUE)
  cat("找到", length(player_files), "個球員逐場數據檔案\n")
  
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
  
  if (length(player_data_list) > 0) {
    player_game_data <- bind_rows(player_data_list)
    cat("球員逐場數據合併完成，總共", nrow(player_game_data), "筆記錄\n")
    return(player_game_data)
  } else {
    cat("無法讀取任何球員逐場數據\n")
    return(NULL)
  }
}

#' 匯入團隊每場比賽統計數據
import_team_game_stats <- function(team_stats_file = "data/performance_team_pergame/all_seasons_all_games_team_stats.csv") {
  cat("\n正在匯入團隊每場比賽統計數據...\n")
  
  if (file.exists(team_stats_file)) {
    team_game_stats <- read_csv(team_stats_file, show_col_types = FALSE)
    cat("成功讀取團隊每場比賽統計數據，共", nrow(team_game_stats), "筆記錄\n")
    
    cat("- 涵蓋賽季：", paste(unique(team_game_stats$SEASON), collapse = ", "), "\n")
    cat("- 球隊數：", length(unique(team_game_stats$TEAM_ID)), "\n")
    cat("- 例行賽場次：", sum(team_game_stats$SEASON_TYPE == "Regular Season", na.rm = TRUE), "\n")
    cat("- 季後賽場次：", sum(team_game_stats$SEASON_TYPE == "Playoffs", na.rm = TRUE), "\n")
    
    return(team_game_stats)
  } else {
    cat("團隊每場比賽統計檔案不存在\n")
    return(NULL)
  }
}

#' 匯入傳球網絡分析所需的所有數據
import_all_nba_data <- function(performance_path = "data/performance_team",
                                player_path = "data/performance_player_pergame",
                                team_stats_file = "data/performance_team_pergame/all_seasons_all_games_team_stats.csv") {
  
  cat("=== NBA傳球網絡分析數據匯入開始 ===\n")
  
  result <- list()
  
  # 原有的三個數據載入
  tryCatch({
    result$team_performance <- import_team_performance(performance_path)
  }, error = function(e) {
    cat("球隊表現數據匯入失敗：", e$message, "\n")
    result$team_performance <- NULL
  })
  
  tryCatch({
    result$player_game_data <- import_player_game_data(player_path)
  }, error = function(e) {
    cat("球員逐場數據匯入失敗：", e$message, "\n")
    result$player_game_data <- NULL
  })
  
  tryCatch({
    result$team_game_stats <- import_team_game_stats(team_stats_file)
  }, error = function(e) {
    cat("團隊每場比賽統計匯入失敗：", e$message, "\n")
    result$team_game_stats <- NULL
  })
  
  # === 新增：載入所有傳球數據 ===
  cat("\n正在匯入所有傳球數據...\n")
  pass_files <- list.files("data/passes_pergame", pattern = "all_players_pass_data_\\d{4}\\.csv", full.names = TRUE)
  if (length(pass_files) > 0) {
    pass_data_list <- list()
    for (file in pass_files) {
      year <- str_extract(basename(file), "\\d{4}")
      tryCatch({
        data <- read_csv(file, show_col_types = FALSE)
        data$GAME_DATE <- as.Date(data$GAME_DATE)
        pass_data_list[[year]] <- data
        cat("成功讀取", year, "年傳球數據\n")
      }, error = function(e) {
        cat("讀取", year, "年傳球數據失敗\n")
      })
    }
    result$all_pass_data <- bind_rows(pass_data_list)
    cat("傳球數據合併完成，共", nrow(result$all_pass_data), "筆記錄\n")
  } else {
    result$all_pass_data <- NULL
  }
  
  # === 新增：載入所有球員屬性 ===
  cat("\n正在匯入所有球員屬性...\n")
  player_files <- list.files("data/players_detailed", pattern = "nba_players_.*_detailed_final\\.json", full.names = TRUE)
  if (length(player_files) > 0) {
    attr_data_list <- list()
    for (file in player_files) {
      season <- str_extract(basename(file), "\\d{4}-\\d{2}")
      tryCatch({
        data <- fromJSON(file)
        if (is.list(data) && !is.data.frame(data)) {
          data <- as.data.frame(do.call(rbind, lapply(data, as.data.frame)))
        }
        if (!"id" %in% colnames(data) && "PERSON_ID" %in% colnames(data)) {
          data$id <- data$PERSON_ID
        }
        if ("headline_stats" %in% colnames(data)) data$headline_stats <- NULL
        data$SEASON <- season
        attr_data_list[[season]] <- data
        cat("成功讀取", season, "賽季球員屬性\n")
      }, error = function(e) {
        cat("讀取", season, "賽季球員屬性失敗\n")
      })
    }
    result$all_player_attributes <- bind_rows(attr_data_list)
    cat("球員屬性合併完成，共", nrow(result$all_player_attributes), "筆記錄\n")
  } else {
    result$all_player_attributes <- NULL
  }
  
  cat("\n=== 數據匯入摘要 ===\n")
  cat("球隊表現數據：", ifelse(is.null(result$team_performance), "未匯入", "已匯入"), "\n")
  cat("球員逐場數據：", ifelse(is.null(result$player_game_data), "未匯入", paste("已匯入", nrow(result$player_game_data), "筆記錄")), "\n")
  cat("團隊每場統計：", ifelse(is.null(result$team_game_stats), "未匯入", paste("已匯入", nrow(result$team_game_stats), "筆記錄")), "\n")
  cat("傳球數據：", ifelse(is.null(result$all_pass_data), "未匯入", paste("已匯入", nrow(result$all_pass_data), "筆記錄")), "\n")
  cat("球員屬性：", ifelse(is.null(result$all_player_attributes), "未匯入", paste("已匯入", nrow(result$all_player_attributes), "筆記錄")), "\n")
  
  return(result)
}

#' 篩選網絡分析用球員
filter_network_players <- function(data, 
                                   season, 
                                   team_abbr,
                                   date_start, 
                                   date_end,
                                   filter_method = "traditional",
                                   min_games = 1,
                                   min_minutes = 15,
                                   top_minutes_players = NULL,
                                   verbose = FALSE) {
  
  original_locale <- Sys.getlocale("LC_TIME")
  Sys.setlocale("LC_TIME", "C")
  
  step1_data <- data %>%
    filter(SEASON == season) %>%
    mutate(parsed_date = as.Date(GAME_DATE, format = "%b %d, %Y"))
  
  Sys.setlocale("LC_TIME", original_locale)
  
  target_start <- as.Date(date_start)
  target_end <- as.Date(date_end)
  
  date_filtered <- step1_data %>%
    filter(!is.na(parsed_date),
           parsed_date >= target_start,
           parsed_date <= target_end)
  
  matchup_parsed <- date_filtered %>%
    mutate(
      actual_team = case_when(
        str_detect(MATCHUP, " @ ") ~ str_extract(MATCHUP, "^[A-Z]{2,3}"),
        str_detect(MATCHUP, " vs\\. ") ~ str_extract(MATCHUP, "^[A-Z]{2,3}"),
        TRUE ~ NA_character_
      )
    )
  
  team_players <- matchup_parsed %>%
    filter(!is.na(actual_team), actual_team == team_abbr)
  
  if (nrow(team_players) == 0) {
    if (verbose) {
      cat("在指定日期範圍內找不到", team_abbr, "隊球員的比賽記錄\n")
    }
    return(data.frame())
  }
  
  player_summary <- team_players %>%
    group_by(PLAYER_NAME) %>%
    summarise(
      games_played = n_distinct(GAME_DATE),
      avg_min = round(mean(MIN, na.rm = TRUE), 1),
      avg_ast = round(mean(AST, na.rm = TRUE), 1),
      avg_pts = round(mean(PTS, na.rm = TRUE), 1),
      .groups = 'drop'
    ) %>%
    arrange(desc(avg_min), desc(games_played))
  
  if (filter_method == "traditional") {
    network_players <- player_summary %>%
      filter(
        games_played >= min_games,
        avg_min >= min_minutes
      )
  } else if (filter_method == "top_minutes") {
    network_players <- player_summary %>%
      head(top_minutes_players)
  } else if (filter_method == "combined") {
    basic_filtered <- player_summary %>%
      filter(
        games_played >= min_games,
        avg_min >= min_minutes
      )
    network_players <- basic_filtered %>%
      head(top_minutes_players)
  }
  
  if (verbose && nrow(network_players) > 0) {
    cat("篩選出", nrow(network_players), "名球員用於網絡分析\n")
    cat("球員名單:", paste(network_players$PLAYER_NAME, collapse = ", "), "\n")
  }
  
  return(network_players)
}

#' 建立傳球網絡
build_pass_network <- function(season_label, 
                               team_abbr, 
                               season_type = "Regular Season",
                               date_start = NULL, 
                               date_end = NULL,
                               player_data = NULL,
                               pass_data = NULL,           # 新增參數
                               player_attributes = NULL,   # 新增參數
                               min_pass = 5,
                               filter_method = "traditional",
                               min_games = 1,
                               min_minutes = 15,
                               top_minutes_players = NULL,
                               verbose = TRUE) {
  
  if (is.null(date_start) || is.null(date_end)) {
    stop("請提供 date_start 和 date_end 參數 (格式: 'YYYY-MM-DD')")
  }
  
  if (is.null(player_data)) {
    stop("請提供 player_data 參數")
  }
  
  # 新增參數檢查
  if (is.null(pass_data)) {
    stop("請提供 pass_data 參數")
  }
  
  if (is.null(player_attributes)) {
    stop("請提供 player_attributes 參數")
  }
  
  if (filter_method %in% c("top_minutes", "combined") && is.null(top_minutes_players)) {
    stop("使用 top_minutes 或 combined 篩選方式時，請提供 top_minutes_players 參數")
  }
  
  if (verbose) {
    cat("=== 建立傳球網絡 ===\n")
    cat("賽季:", season_label, "\n")
    cat("球隊:", team_abbr, "\n")
    cat("賽季類型:", season_type, "\n")
    cat("日期範圍:", date_start, "至", date_end, "\n")
    cat("篩選方式:", filter_method, "\n")
    cat("最少傳球次數:", min_pass, "\n")
  }
  
  filtered_players <- filter_network_players(
    data = player_data,
    season = season_label,
    team_abbr = team_abbr,
    date_start = date_start,
    date_end = date_end,
    filter_method = filter_method,
    min_games = min_games,
    min_minutes = min_minutes,
    top_minutes_players = top_minutes_players,
    verbose = verbose
  )
  
  if (nrow(filtered_players) == 0) {
    stop("沒有符合篩選條件的球員")
  }
  
  # 使用預載數據而非讀取檔案
  pass_edges <- pass_data
  season_player_attributes <- player_attributes %>%
    filter(SEASON == season_label)
  
  if (nrow(season_player_attributes) == 0) {
    stop(paste("找不到", season_label, "賽季的球員屬性數據"))
  }
  
  if (!"id" %in% colnames(season_player_attributes) && "PERSON_ID" %in% colnames(season_player_attributes)) {
    season_player_attributes$id <- season_player_attributes$PERSON_ID
  }
  
  pass_edges$GAME_DATE <- as.Date(pass_edges$GAME_DATE)
  date_start <- as.Date(date_start)
  date_end <- as.Date(date_end)
  
  filtered_edges <- pass_edges %>%
    filter(
      SEASON_TYPE == season_type,
      TEAM_ABBREVIATION == team_abbr,
      GAME_DATE >= date_start,
      GAME_DATE <= date_end
    )
  
  if (nrow(filtered_edges) == 0) {
    stop("在指定條件下沒有找到傳球數據")
  }
  
  player_name_to_id <- season_player_attributes %>%
    select(id, DISPLAY_FIRST_LAST) %>%
    rename(PLAYER_ID = id, PLAYER_NAME = DISPLAY_FIRST_LAST)
  
  filtered_player_ids <- filtered_players %>%
    left_join(player_name_to_id, by = "PLAYER_NAME") %>%
    filter(!is.na(PLAYER_ID)) %>%
    pull(PLAYER_ID)
  
  if (length(filtered_player_ids) == 0) {
    stop("無法匹配球員ID，請檢查球員姓名格式")
  }
  
  network_edges <- filtered_edges %>%
    filter(
      PLAYER_ID %in% filtered_player_ids,
      PASS_TEAMMATE_PLAYER_ID %in% filtered_player_ids
    )
  
  if (nrow(network_edges) == 0) {
    stop("篩選球員之間沒有傳球數據")
  }
  
  pass_summary <- network_edges %>%
    group_by(PLAYER_ID, PASS_TEAMMATE_PLAYER_ID) %>%
    summarise(
      total_passes = sum(PASS),
      total_assists = sum(AST),
      .groups = "drop"
    ) %>%
    filter(total_passes >= min_pass)
  
  if (nrow(pass_summary) == 0) {
    stop(paste("沒有符合最少傳球次數條件的連結 (門檻:", min_pass, ")"))
  }
  
  valid_player_ids <- unique(c(pass_summary$PLAYER_ID, pass_summary$PASS_TEAMMATE_PLAYER_ID))
  network_player_attributes <- season_player_attributes %>%
    filter(id %in% valid_player_ids)
  
  if ("headline_stats" %in% colnames(network_player_attributes) && 
      is.list(network_player_attributes$headline_stats)) {
    network_player_attributes$headline_stats <- NULL
  }
  
  rownames(network_player_attributes) <- as.character(network_player_attributes$id)
  
  edges_df <- data.frame(
    from = as.character(pass_summary$PLAYER_ID),
    to = as.character(pass_summary$PASS_TEAMMATE_PLAYER_ID),
    total_passes = pass_summary$total_passes,
    total_assists = pass_summary$total_assists,
    stringsAsFactors = FALSE
  )
  
  pass_network <- graph_from_data_frame(d = edges_df, directed = TRUE, vertices = network_player_attributes)
  
  # 儲存所有篩選參數到網絡屬性
  graph_attr(pass_network, "team_abbr") <- team_abbr
  graph_attr(pass_network, "season_label") <- season_label
  graph_attr(pass_network, "date_start") <- as.character(date_start)
  graph_attr(pass_network, "date_end") <- as.character(date_end)
  graph_attr(pass_network, "filter_method") <- filter_method
  graph_attr(pass_network, "min_pass") <- min_pass
  graph_attr(pass_network, "min_games") <- min_games
  graph_attr(pass_network, "min_minutes") <- min_minutes
  graph_attr(pass_network, "top_minutes_players") <- top_minutes_players
  
  if (verbose) {
    cat("網絡建構完成:\n")
    cat("- 球員數:", vcount(pass_network), "\n")
    cat("- 傳球連結數:", ecount(pass_network), "\n")
    cat("- 總傳球次數:", sum(E(pass_network)$total_passes), "\n")
    cat("- 總助攻次數:", sum(E(pass_network)$total_assists), "\n")
  }
  
  return(pass_network)
}

#' 繪製NBA傳球網絡
plot_pass_network <- function(network) {
  
  if (!is.igraph(network)) {
    stop("network parameter must be an igraph object")
  }
  
  if (vcount(network) == 0) {
    stop("No nodes in the network")
  }
  
  if ("total_assists" %in% edge_attr_names(network)) {
    node_assists <- rep(0, vcount(network))
    names(node_assists) <- V(network)$name
    
    edge_list <- get.edgelist(network, names = TRUE)
    for (i in 1:nrow(edge_list)) {
      from_player <- edge_list[i, 1]
      assists <- E(network)$total_assists[i]
      if (from_player %in% names(node_assists)) {
        node_assists[from_player] <- node_assists[from_player] + assists
      }
    }
    
    if (max(node_assists) > 0) {
      V(network)$size <- scales::rescale(node_assists, to = c(8, 20))
    } else {
      V(network)$size <- 12
    }
    
    V(network)$node_assists <- node_assists[V(network)$name]
    
  } else {
    V(network)$size <- 12
    V(network)$node_assists <- 0
  }
  
  V(network)$color <- "skyblue"
  
  if ("total_passes" %in% edge_attr_names(network)) {
    E(network)$width <- scales::rescale(E(network)$total_passes, to = c(1, 3))
  } else {
    E(network)$width <- 2
  }
  
  set.seed(123)
  layout <- layout_with_fr(network)
  
  team_abbr <- graph_attr(network, "team_abbr") %||% "TEAM"
  date_start <- graph_attr(network, "date_start") %||% ""
  date_end <- graph_attr(network, "date_end") %||% ""
  filter_method <- graph_attr(network, "filter_method") %||% ""
  min_pass <- graph_attr(network, "min_pass") %||% ""
  
  # 從網絡中取得篩選參數
  min_games <- graph_attr(network, "min_games") %||% NULL
  min_minutes <- graph_attr(network, "min_minutes") %||% NULL
  top_minutes_players <- graph_attr(network, "top_minutes_players") %||% NULL
  
  if (date_start != "" && date_end != "") {
    if (date_start == date_end) {
      date_range <- format(as.Date(date_start), "%Y-%m-%d")
    } else {
      date_range <- paste(format(as.Date(date_start), "%Y-%m-%d"), "to", 
                          format(as.Date(date_end), "%Y-%m-%d"))
    }
  } else {
    date_range <- ""
  }
  
  # 根據篩選方式產生具體的篩選描述
  filter_description <- ""
  if (filter_method == "traditional") {
    parts <- c()
    if (!is.null(min_games)) parts <- c(parts, paste0("≥", min_games, " Games"))
    if (!is.null(min_minutes)) parts <- c(parts, paste0("≥", min_minutes, " Min/Game"))
    filter_description <- paste(parts, collapse = " & ")
  } else if (filter_method == "top_minutes") {
    if (!is.null(top_minutes_players)) {
      filter_description <- paste0("Top ", top_minutes_players, " Minutes")
    }
  } else if (filter_method == "combined") {
    parts <- c()
    if (!is.null(min_games)) parts <- c(parts, paste0("≥", min_games, " Games"))
    if (!is.null(min_minutes)) parts <- c(parts, paste0("≥", min_minutes, " Min/Game"))
    if (!is.null(top_minutes_players)) parts <- c(parts, paste0("Top ", top_minutes_players))
    filter_description <- paste(parts, collapse = " & ")
  }
  
  # 組合標題（移除 Pass Network 和賽季）
  title_parts <- c(team_abbr)
  if (date_range != "") title_parts <- c(title_parts, date_range)
  if (filter_description != "") title_parts <- c(title_parts, filter_description)
  if (min_pass != "") title_parts <- c(title_parts, paste0("Min ", min_pass, " Passes"))
  
  main_title <- paste(title_parts, collapse = " | ")
  
  # 調整邊距，為底部圖例留出更多空間
  par(mar = c(4.5, 1, 4, 1))
  
  plot(network,
       layout = layout,
       vertex.label = V(network)$DISPLAY_FIRST_LAST,
       vertex.label.color = "black",
       vertex.label.cex = 0.8,
       vertex.size = V(network)$size,
       vertex.color = V(network)$color,
       edge.width = E(network)$width,
       edge.arrow.size = 0.5,
       edge.curved = 0.2,
       edge.color = adjustcolor("grey30", alpha.f = 0.6),
       main = main_title
  )
  
  # 將圖例放在圖的下方中央，加上邊框並增加距離
  if ("node_assists" %in% vertex_attr_names(network)) {
    max_assists <- max(V(network)$node_assists, na.rm = TRUE)
    min_assists <- min(V(network)$node_assists, na.rm = TRUE)
    
    # 在圖的下方添加圖例，帶邊框
    legend("bottom", 
           legend = c(
             paste("Node Size: Assists (", min_assists, "-", max_assists, ")"),
             paste("Edge Width: Passes (", min(E(network)$total_passes), "-", max(E(network)$total_passes), ")")
           ),
           pch = c(21, NA),
           lty = c(NA, 1),
           lwd = c(NA, 3),
           pt.bg = "skyblue",
           pt.cex = c(1.5, NA),
           col = c("black", adjustcolor("grey30", alpha.f = 0.6)),
           bty = "o",        # 顯示邊框
           bg = "white",     # 圖例背景色
           box.col = "gray50", # 邊框顏色
           box.lwd = 1,      # 邊框線寬
           cex = 0.8,
           horiz = TRUE,     # 水平排列圖例項目
           xpd = TRUE,       # 允許圖例超出繪圖區域
           inset = c(0, -0.15) # 負值讓圖例離圖表更遠
    )
  }
  
  # 恢復預設邊距
  par(mar = c(5, 4, 4, 2) + 0.1)
  
  cat("\n=== 網絡統計 ===\n")
  cat("球員數:", vcount(network), "\n")
  cat("傳球連結數:", ecount(network), "\n")
  if ("total_passes" %in% edge_attr_names(network)) {
    cat("總傳球次數:", sum(E(network)$total_passes), "\n")
    cat("平均傳球次數:", round(mean(E(network)$total_passes), 1), "\n")
  }
  if ("node_assists" %in% vertex_attr_names(network)) {
    cat("總助攻次數:", sum(V(network)$node_assists), "\n")
    top_assisters <- head(sort(V(network)$node_assists, decreasing = TRUE), 3)
    cat("前三名助攻:", paste(names(top_assisters), "(", top_assisters, ")", collapse = ", "), "\n")
  }
}

# === 執行分析 ===

# 1. 載入數據
cat("開始匯入NBA分析所需數據...\n")
nba_data <- import_all_nba_data()

if (!is.null(nba_data$team_performance)) {
  regular_season_stats <- nba_data$team_performance$regular_season_stats
  playoff_stats <- nba_data$team_performance$playoff_stats
  league_standings <- nba_data$team_performance$league_standings
}

if (!is.null(nba_data$player_game_data)) {
  player_game_data <- nba_data$player_game_data
}

if (!is.null(nba_data$team_game_stats)) {
  team_game_stats <- nba_data$team_game_stats
}

# 新增：建立傳球數據和球員屬性的全域變數
if (!is.null(nba_data$all_pass_data)) {
  all_pass_data <- nba_data$all_pass_data
}

if (!is.null(nba_data$all_player_attributes)) {
  all_player_attributes <- nba_data$all_player_attributes
}

cat("\n數據匯入完成！開始建立傳球網絡...\n")

# 2. 建立網絡
network <- build_pass_network(
  season_label = "2024-25",
  team_abbr = "DAL",
  date_start = "2024-12-23", 
  date_end = "2024-12-23",
  player_data = player_game_data,
  min_pass = 0,
  pass_data = all_pass_data,           # 使用全域變數
  player_attributes = all_player_attributes,  # 使用全域變數
  filter_method = "top_minutes",
  top_minutes_players = 5
)

# 3. 繪製網絡
plot_pass_network(network)

















calculate_network_metrics <- function(network, 
                                      season_label, 
                                      team_abbr, 
                                      game_date, 
                                      season_type) {
  
  # 基本網絡資訊
  num_nodes <- vcount(network)
  num_edges <- ecount(network)
  
  # 如果網絡為空，返回空的結果
  if (num_nodes == 0) {
    empty_result <- data.frame(
      team_abbr = team_abbr,
      game_id = NA,
      game_date = game_date,
      opponent = "Unknown",
      nodes = 0,
      edges = 0,
      density = 0,
      vertex_connectivity = 0,
      edge_connectivity = 0,
      components = 0,
      max_component_size = 0,
      biconnected_components = 0,
      cohesive_blocks = 0,
      max_cohesion_value = 0,
      in_degree_centralization = 0,
      out_degree_centralization = 0,
      in_closeness_centralization = 0,
      out_closeness_centralization = 0,
      betweenness_centralization = 0,
      eigenvector_centralization = 0,
      walktrap_communities = 0,
      walktrap_modularity = 0,
      edge_betweenness_communities = 0,
      edge_betweenness_modularity = 0,
      louvain_communities = 0,
      louvain_modularity = 0,
      best_modularity = 0,
      season = season_label,
      season_type = season_type,
      stringsAsFactors = FALSE
    )
    return(empty_result)
  }
  
  # 檢查是否有傳球次數權重
  has_weights <- "total_passes" %in% edge_attr_names(network) && num_edges > 0
  
  # 如果沒有權重但有邊，設定預設權重為1
  if (!has_weights && num_edges > 0) {
    E(network)$total_passes <- rep(1, num_edges)
    has_weights <- TRUE
  }
  
  # === 基本網絡指標（加權版本）===
  
  # 修正的加權密度計算：實際權重總和 / 理論最大權重總和
  if (has_weights && num_edges > 0) {
    actual_weight_sum <- sum(E(network)$total_passes, na.rm = TRUE)
    max_possible_edges <- num_nodes * (num_nodes - 1)
    
    # 理論最大權重總和 = 最大可能邊數 × 觀察到的最大權重
    max_observed_weight <- max(E(network)$total_passes, na.rm = TRUE)
    theoretical_max_weight_sum <- max_possible_edges * max_observed_weight
    
    density_score <- ifelse(theoretical_max_weight_sum > 0, 
                            actual_weight_sum / theoretical_max_weight_sum, 0)
  } else {
    density_score <- ifelse(num_edges > 0, edge_density(network), 0)
  }
  
  # 加權連通性指標
  # 對於加權圖，頂點連通性基於最小權重切割
  vertex_connectivity <- tryCatch({
    if (has_weights && num_edges > 0) {
      # 使用最小權重強度作為連通性的近似
      strengths <- strength(network, weights = E(network)$total_passes)
      min_strength <- min(strengths[strengths > 0], na.rm = TRUE)
      ifelse(is.finite(min_strength), max(1, floor(min_strength / mean(E(network)$total_passes))), 0)
    } else {
      vertex_connectivity(network)
    }
  }, error = function(e) 0)
  
  # 修正的邊連通性：基於最小權重切割的真實連通性定義
  edge_connectivity <- tryCatch({
    if (has_weights && num_edges > 0 && num_nodes > 1) {
      # 計算所有可能的s-t最小切割，找出全域最小切割
      min_cut_value <- Inf
      
      # 對於小型網絡，檢查所有節點對的最小切割
      if (num_nodes <= 10) {
        for (s in 1:(num_nodes-1)) {
          for (t in (s+1):num_nodes) {
            tryCatch({
              # 使用最大流-最小切割定理計算s-t最小切割
              cut_value <- max_flow(network, source = s, target = t, 
                                    capacity = E(network)$total_passes)$value
              min_cut_value <- min(min_cut_value, cut_value)
            }, error = function(e) {})
          }
        }
      } else {
        # 對於大型網絡，使用啟發式方法：抽樣節點對
        sample_size <- min(20, num_nodes)
        sampled_nodes <- sample(1:num_nodes, sample_size)
        
        for (i in 1:(length(sampled_nodes)-1)) {
          for (j in (i+1):length(sampled_nodes)) {
            s <- sampled_nodes[i]
            t <- sampled_nodes[j]
            tryCatch({
              cut_value <- max_flow(network, source = s, target = t, 
                                    capacity = E(network)$total_passes)$value
              min_cut_value <- min(min_cut_value, cut_value)
            }, error = function(e) {})
          }
        }
      }
      
      # 如果無法計算最小切割，使用最小權重邊作為下界
      if (is.infinite(min_cut_value)) {
        min_cut_value <- min(E(network)$total_passes, na.rm = TRUE)
      }
      
      min_cut_value
    } else if (num_edges > 0) {
      # 無權重圖的標準邊連通性
      edge_connectivity(network)
    } else {
      0
    }
  }, error = function(e) {
    # 錯誤處理：返回最小權重邊
    if (has_weights && num_edges > 0) {
      min(E(network)$total_passes, na.rm = TRUE)
    } else {
      0
    }
  })
  
  # 組件分析
  components_obj <- components(network)
  num_components <- components_obj$no
  max_component_size <- max(components_obj$csize)
  
  # 雙連通組件
  biconnected_components <- tryCatch({
    length(biconnected_components(network))
  }, error = function(e) 0)
  
  # 凝聚塊分析
  cohesive_blocks_count <- 0
  max_cohesion_value <- 0
  tryCatch({
    cb <- cohesive_blocks(network)
    cohesive_blocks_count <- length(cb)
    if (length(cb) > 0) {
      if (has_weights) {
        max_cohesion_value <- mean(E(network)$total_passes, na.rm = TRUE)
      } else {
        max_cohesion_value <- max(cohesion(cb), na.rm = TRUE)
      }
    }
  }, error = function(e) {
    # 保持預設值
  })
  
  # === 加權中心化指標（基於Freeman centralization公式）===
  
  # 加權度數中心化：使用強度(strength)替代度數
  in_degree_centralization <- tryCatch({
    if (has_weights && num_edges > 0) {
      in_strengths <- strength(network, mode = "in", weights = E(network)$total_passes)
      if (length(in_strengths) > 1) {
        max_strength <- max(in_strengths, na.rm = TRUE)
        sum_diff <- sum(max_strength - in_strengths, na.rm = TRUE)
        # Freeman centralization公式的分母
        theoretical_max <- (num_nodes - 1) * max_strength
        ifelse(theoretical_max > 0, sum_diff / theoretical_max, 0)
      } else {
        0
      }
    } else {
      centralization.degree(network, mode = "in")$centralization
    }
  }, error = function(e) 0)
  
  out_degree_centralization <- tryCatch({
    if (has_weights && num_edges > 0) {
      out_strengths <- strength(network, mode = "out", weights = E(network)$total_passes)
      if (length(out_strengths) > 1) {
        max_strength <- max(out_strengths, na.rm = TRUE)
        sum_diff <- sum(max_strength - out_strengths, na.rm = TRUE)
        theoretical_max <- (num_nodes - 1) * max_strength
        ifelse(theoretical_max > 0, sum_diff / theoretical_max, 0)
      } else {
        0
      }
    } else {
      centralization.degree(network, mode = "out")$centralization
    }
  }, error = function(e) 0)
  
  # === 完全按照原方法的4個中心性計算（無加權）===
  
  # 鄰近中心化（接受）
  in_closeness_centralization <- 0
  tryCatch({
    cent_inclo_social <- centr_clo(graph = network, mode = "in", normalized = TRUE)
    in_closeness_centralization <- cent_inclo_social$centralization
  }, error = function(e) {
    in_closeness_centralization <- 0
  })
  
  # 鄰近中心化（選擇）
  out_closeness_centralization <- 0
  tryCatch({
    cent_outclo_social <- centr_clo(graph = network, mode = "out", normalized = TRUE)
    out_closeness_centralization <- cent_outclo_social$centralization
  }, error = function(e) {
    out_closeness_centralization <- 0
  })
  
  # 中介中心化
  betweenness_centralization <- 0
  tryCatch({
    cent_betw_social <- centr_betw(graph = network, directed = TRUE, normalized = TRUE)
    betweenness_centralization <- cent_betw_social$centralization
  }, error = function(e) {
    betweenness_centralization <- 0
  })
  
  # 特徵向量中心化
  eigenvector_centralization <- 0
  tryCatch({
    centr_eigen_social <- centr_eigen(graph = network, directed = FALSE, normalized = TRUE)
    eigenvector_centralization <- centr_eigen_social$centralization
  }, error = function(e) {
    eigenvector_centralization <- 0
  })
  
  # 處理NA值
  if (is.na(in_closeness_centralization)) in_closeness_centralization <- 0
  if (is.na(out_closeness_centralization)) out_closeness_centralization <- 0
  if (is.na(betweenness_centralization)) betweenness_centralization <- 0
  if (is.na(eigenvector_centralization)) eigenvector_centralization <- 0
  
  # === 加權社群檢測指標 ===
  
  # 初始化社群指標
  walktrap_communities <- 0
  walktrap_modularity <- 0
  edge_betweenness_communities <- 0
  edge_betweenness_modularity <- 0
  louvain_communities <- 0
  louvain_modularity <- 0
  
  if (num_edges > 0 && num_nodes > 1) {
    # 轉為無向圖進行社群檢測
    tryCatch({
      network_undirected <- as.undirected(network, mode = "collapse", edge.attr.comb = "sum")
      
      # 檢查無向圖權重
      undirected_has_weights <- "total_passes" %in% edge_attr_names(network_undirected) && 
        ecount(network_undirected) > 0
      
      if (!undirected_has_weights && ecount(network_undirected) > 0) {
        E(network_undirected)$total_passes <- rep(1, ecount(network_undirected))
        undirected_has_weights <- TRUE
      }
      
      # 加權Walktrap：基於隨機遊走，權重影響遊走機率
      tryCatch({
        if (undirected_has_weights && all(E(network_undirected)$total_passes > 0)) {
          comm_walktrap <- cluster_walktrap(network_undirected, 
                                            weights = E(network_undirected)$total_passes, 
                                            steps = 4)
          walktrap_communities <- length(comm_walktrap)
          walktrap_modularity <- modularity(comm_walktrap)
        }
      }, error = function(e) {})
      
      # 加權Edge Betweenness：使用權重倒數計算介數
      tryCatch({
        if (undirected_has_weights && all(E(network_undirected)$total_passes > 0)) {
          inv_weights <- 1 / E(network_undirected)$total_passes
          comm_edge_betweenness <- cluster_edge_betweenness(network_undirected, 
                                                            weights = inv_weights)
          edge_betweenness_communities <- length(comm_edge_betweenness)
          edge_betweenness_modularity <- modularity(comm_edge_betweenness)
        }
      }, error = function(e) {})
      
      # 加權Louvain：直接優化加權模組化度
      tryCatch({
        if (undirected_has_weights && all(E(network_undirected)$total_passes > 0)) {
          comm_louvain <- cluster_louvain(network_undirected, 
                                          weights = E(network_undirected)$total_passes)
          louvain_communities <- length(comm_louvain)
          louvain_modularity <- modularity(comm_louvain)
        }
      }, error = function(e) {})
      
    }, error = function(e) {})
  }
  
  # 最佳模組化度
  best_modularity <- max(walktrap_modularity, edge_betweenness_modularity, louvain_modularity, na.rm = TRUE)
  if (is.infinite(best_modularity) || is.na(best_modularity)) {
    best_modularity <- 0
  }
  
  # === 建構結果資料框 ===
  
  network_summary <- data.frame(
    team_abbr = team_abbr,
    game_id = NA,
    game_date = game_date,
    opponent = "Unknown",
    nodes = num_nodes,
    edges = num_edges,
    density = density_score,
    vertex_connectivity = vertex_connectivity,
    edge_connectivity = edge_connectivity,
    components = num_components,
    max_component_size = max_component_size,
    biconnected_components = biconnected_components,
    cohesive_blocks = cohesive_blocks_count,
    max_cohesion_value = max_cohesion_value,
    in_degree_centralization = in_degree_centralization,
    out_degree_centralization = out_degree_centralization,
    in_closeness_centralization = in_closeness_centralization,
    out_closeness_centralization = out_closeness_centralization,
    betweenness_centralization = betweenness_centralization,
    eigenvector_centralization = eigenvector_centralization,
    walktrap_communities = walktrap_communities,
    walktrap_modularity = walktrap_modularity,
    edge_betweenness_communities = edge_betweenness_communities,
    edge_betweenness_modularity = edge_betweenness_modularity,
    louvain_communities = louvain_communities,
    louvain_modularity = louvain_modularity,
    best_modularity = best_modularity,
    season = season_label,
    season_type = season_type,
    stringsAsFactors = FALSE
  )
  
  return(network_summary)
}








# 修正版批量分析傳球網絡（使用原本的繪圖函數）
batch_analyze_pass_networks <- function(year_start = 2020,
                                        year_end = 2024,
                                        top_minutes_players = 5,
                                        min_pass = 1,
                                        season_types = c("Regular Season", "Playoffs"),
                                        pass_data = NULL,
                                        player_data = NULL,
                                        player_attributes = NULL,
                                        verbose = TRUE) {
  
  if (is.null(pass_data) || is.null(player_data) || is.null(player_attributes)) {
    stop("請提供 pass_data, player_data, 和 player_attributes 參數")
  }
  
  # 創建輸出目錄結構的函數
  create_output_dirs <- function(season_label, season_type, dir_type = "network_plots") {
    season_type_dir <- ifelse(season_type == "Regular Season", "regular", "playoffs")
    base_dir <- file.path("data", "all_passes_per_game", season_label, season_type_dir, "plot", dir_type)
    if (!dir.exists(base_dir)) {
      dir.create(base_dir, recursive = TRUE)
    }
    return(base_dir)
  }
  
  # 創建指標輸出目錄的函數
  create_indicator_dirs <- function(season_label, season_type) {
    season_type_dir <- ifelse(season_type == "Regular Season", "regular", "playoffs")
    indicator_dir <- file.path("data", "all_passes_per_game", season_label, season_type_dir, "indicator")
    if (!dir.exists(indicator_dir)) {
      dir.create(indicator_dir, recursive = TRUE)
    }
    return(indicator_dir)
  }
  
  # 獲取對手資訊的函數
  get_opponent <- function(game_id, team_abbr, pass_data) {
    game_teams <- pass_data %>%
      filter(GAME_ID == game_id) %>%
      pull(TEAM_ABBREVIATION) %>%
      unique()
    
    if (length(game_teams) <= 1) return("Unknown")
    
    opponent <- game_teams[game_teams != team_abbr]
    return(ifelse(length(opponent) > 0, opponent[1], "Unknown"))
  }
  
  cat("=== 批量傳球網絡分析 ===\n")
  cat("年份範圍:", year_start, "-", year_end, "\n")
  cat("賽季類型:", paste(season_types, collapse = ", "), "\n")
  cat("前幾名球員:", top_minutes_players, "\n")
  cat("最少傳球次數:", min_pass, "\n")
  
  # 儲存所有結果
  all_results <- data.frame()
  
  # 雙重迴圈：先賽季類型，再年份
  for (season_type in season_types) {
    cat("\n====== 開始處理賽季類型:", season_type, "======\n")
    
    # 提取該賽季類型的可用組合
    available_combinations <- pass_data %>%
      filter(SEASON_TYPE == season_type) %>%
      mutate(
        year = as.numeric(str_extract(SEASON, "^\\d{4}")),
        season_label = SEASON
      ) %>%
      filter(year >= year_start, year <= year_end) %>%
      select(season_label, TEAM_ABBREVIATION, GAME_DATE, GAME_ID) %>%
      distinct() %>%
      arrange(season_label, TEAM_ABBREVIATION, GAME_DATE)
    
    if (nrow(available_combinations) == 0) {
      cat("在", season_type, "中找不到指定年份範圍的傳球數據，跳過\n")
      next
    }
    
    cat("找到", nrow(available_combinations), "筆", season_type, "組合\n")
    
    # 按賽季分組處理
    seasons <- unique(available_combinations$season_label)
    
    for (season_label in seasons) {
      cat("\n--- 處理賽季:", season_label, "-", season_type, "---\n")
      
      # 建立輸出目錄
      base_dir <- create_output_dirs(season_label, season_type, "network_plots")
      indicator_dir <- create_indicator_dirs(season_label, season_type)
      walktrap_dir <- create_output_dirs(season_label, season_type, "walktrap")
      edge_betweenness_dir <- create_output_dirs(season_label, season_type, "edge_betweenness")
      louvain_dir <- create_output_dirs(season_label, season_type, "louvain")
      
      # 獲取該賽季該類型的組合
      season_combinations <- available_combinations %>%
        filter(season_label == !!season_label)
      
      # 按球隊分組處理
      teams <- unique(season_combinations$TEAM_ABBREVIATION)
      season_metrics <- data.frame()
      
      for (team_abbr in teams) {
        cat("處理球隊:", team_abbr, "(", season_type, ")\n")
        
        # 創建球隊目錄
        team_dirs <- list(
          base = file.path(base_dir, team_abbr),
          indicator = file.path(indicator_dir, team_abbr),
          walktrap = file.path(walktrap_dir, team_abbr),
          edge_betweenness = file.path(edge_betweenness_dir, team_abbr),
          louvain = file.path(louvain_dir, team_abbr)
        )
        
        for (dir in team_dirs) {
          if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
        }
        
        # 獲取該球隊的比賽
        team_games <- season_combinations %>%
          filter(TEAM_ABBREVIATION == team_abbr)
        
        team_metrics <- data.frame()
        
        for (i in 1:nrow(team_games)) {
          game_info <- team_games[i, ]
          game_id <- game_info$GAME_ID
          game_date <- as.Date(game_info$GAME_DATE)
          
          tryCatch({
            # 建立網絡
            network <- build_pass_network(
              season_label = season_label,
              team_abbr = team_abbr,
              season_type = season_type,
              date_start = as.character(game_date),
              date_end = as.character(game_date),
              player_data = player_data,
              pass_data = pass_data,
              player_attributes = player_attributes,
              min_pass = min_pass,
              filter_method = "top_minutes",
              top_minutes_players = top_minutes_players,
              verbose = FALSE
            )
            
            # 獲取對手
            opponent <- get_opponent(game_id, team_abbr, pass_data)
            
            # 計算網絡指標
            network_metrics <- calculate_network_metrics(
              network = network,
              season_label = season_label,
              team_abbr = team_abbr,
              game_date = as.character(game_date),
              season_type = season_type
            )
            
            # 添加額外資訊（修正這裡）
            network_metrics$game_id <- game_id
            network_metrics$opponent <- opponent
            
            team_metrics <- rbind(team_metrics, network_metrics)
            
            # 繪製網絡圖（使用原本的函數）
            season_type_code <- ifelse(season_type == "Regular Season", "reg", "po")
            game_date_formatted <- format(game_date, "%Y%m%d")
            
            # 主要網絡圖 - 使用您原本的 plot_pass_network 函數
            output_file <- file.path(team_dirs$base, 
                                     paste0(team_abbr, "_", season_type_code, "_pass_network_", game_date_formatted, ".png"))
            
            png(output_file, width = 1200, height = 1000, res = 100)
            plot_pass_network(network)  # 使用您原本的函數！
            dev.off()
            
            # 社群檢測圖
            network_undirected <- as.undirected(network, mode = "collapse")
            
            # Walktrap
            tryCatch({
              comm_walktrap <- cluster_walktrap(network, steps = 4)
              walktrap_file <- file.path(team_dirs$walktrap, 
                                         paste0(team_abbr, "_", season_type_code, "_walktrap_", game_date_formatted, ".png"))
              png(walktrap_file, width = 1200, height = 1000, res = 100)
              par(mar = c(1, 1, 4, 1))
              
              set.seed(123)
              layout <- layout_with_fr(network)
              
              season_type_label <- ifelse(season_type == "Regular Season", "Regular Season", "Playoffs")
              plot(comm_walktrap, network, layout = layout,
                   vertex.label = V(network)$DISPLAY_FIRST_LAST,
                   vertex.label.color = "black", vertex.label.cex = 0.8,
                   vertex.size = V(network)$size, edge.width = E(network)$width,
                   edge.arrow.size = 0.05, edge.curved = 0.2,
                   main = paste0(team_abbr, " - Walktrap Communities - ", 
                                 format(game_date, "%Y-%m-%d"), " (vs ", opponent, ")"))
              mtext(paste0("Season: ", season_label, " - ", season_type_label), 
                    side = 1, line = -1, adj = 0.02, cex = 0.8)
              dev.off()
            }, error = function(e) cat("Walktrap 繪圖失敗\n"))
            
            # Edge Betweenness
            tryCatch({
              comm_edge_betweenness <- cluster_edge_betweenness(network)
              edge_betweenness_file <- file.path(team_dirs$edge_betweenness, 
                                                 paste0(team_abbr, "_", season_type_code, "_edge_betweenness_", game_date_formatted, ".png"))
              png(edge_betweenness_file, width = 1200, height = 1000, res = 100)
              par(mar = c(1, 1, 4, 1))
              
              set.seed(123)
              layout <- layout_with_fr(network)
              
              plot(comm_edge_betweenness, network, layout = layout,
                   vertex.label = V(network)$DISPLAY_FIRST_LAST,
                   vertex.label.color = "black", vertex.label.cex = 0.8,
                   vertex.size = V(network)$size, edge.width = E(network)$width,
                   edge.arrow.size = 0.05, edge.curved = 0.2,
                   main = paste0(team_abbr, " - Edge Betweenness Communities - ", 
                                 format(game_date, "%Y-%m-%d"), " (vs ", opponent, ")"))
              mtext(paste0("Season: ", season_label, " - ", season_type_label), 
                    side = 1, line = -1, adj = 0.02, cex = 0.8)
              dev.off()
            }, error = function(e) cat("Edge Betweenness 繪圖失敗\n"))
            
            # Louvain
            tryCatch({
              comm_louvain <- cluster_louvain(network_undirected, resolution = 1)
              louvain_file <- file.path(team_dirs$louvain, 
                                        paste0(team_abbr, "_", season_type_code, "_louvain_", game_date_formatted, ".png"))
              png(louvain_file, width = 1200, height = 1000, res = 100)
              par(mar = c(1, 1, 4, 1))
              
              set.seed(123)
              layout <- layout_with_fr(network)
              
              plot(comm_louvain, network_undirected, layout = layout,
                   vertex.label = V(network)$DISPLAY_FIRST_LAST,
                   vertex.label.color = "black", vertex.label.cex = 0.8,
                   vertex.size = V(network)$size, edge.width = E(network)$width,
                   main = paste0(team_abbr, " - Louvain Communities - ", 
                                 format(game_date, "%Y-%m-%d"), " (vs ", opponent, ")"))
              mtext(paste0("Season: ", season_label, " - ", season_type_label), 
                    side = 1, line = -1, adj = 0.02, cex = 0.8)
              dev.off()
            }, error = function(e) cat("Louvain 繪圖失敗\n"))
            
            if (verbose && i %% 10 == 0) {
              cat("  已處理", i, "/", nrow(team_games), "場比賽\n")
            }
            
          }, error = function(e) {
            cat("處理失敗 - 球隊:", team_abbr, "比賽:", game_id, "錯誤:", e$message, "\n")
          })
        }
        
        # 儲存球隊指標
        if (nrow(team_metrics) > 0) {
          metrics_file <- file.path(team_dirs$indicator, paste0("network_metrics_", team_abbr, ".csv"))
          write.csv(team_metrics, metrics_file, row.names = FALSE)
          cat("已儲存", team_abbr, "的", nrow(team_metrics), "筆", season_type, "指標\n")
          
          season_metrics <- rbind(season_metrics, team_metrics)
        }
      }
      
      all_results <- rbind(all_results, season_metrics)
      cat("賽季", season_label, "-", season_type, "處理完成\n")
    }
  }
  
  # 合併並儲存整合指標
  if (nrow(all_results) > 0) {
    output_dir <- "data/all_passes_per_game"
    if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
    
    # 根據年份範圍命名
    if (year_start == year_end) {
      year_suffix <- as.character(year_start)
    } else {
      year_suffix <- paste0(year_start, "_to_", year_end)
    }
    
    output_file <- file.path(output_dir, paste0("network_metrics_", year_suffix, ".csv"))
    write.csv(all_results, output_file, row.names = FALSE)
    
    cat("\n=== 分析完成 ===\n")
    cat("整合指標已儲存至:", output_file, "\n")
    cat("總計處理:", nrow(all_results), "筆記錄\n")
    cat("涵蓋賽季:", paste(unique(all_results$season), collapse = ", "), "\n")
    cat("涵蓋賽季類型:", paste(unique(all_results$season_type), collapse = ", "), "\n")
    cat("涵蓋球隊:", length(unique(all_results$team)), "支\n")
  }
  
  return(all_results)
}



# 修正版載入批量指標函數
load_batch_metrics <- function(base_dir = "data/all_passes_per_game", 
                               year_suffix = "2024") {
  
  if (!dir.exists(base_dir)) {
    stop("基礎資料夾不存在:", base_dir)
  }
  
  # 尋找整合指標檔案
  metrics_file <- file.path(base_dir, paste0("network_metrics_", year_suffix, ".csv"))
  
  if (!file.exists(metrics_file)) {
    # 如果找不到指定檔案，列出所有可用的指標檔案
    available_files <- list.files(base_dir, pattern = "network_metrics_.*\\.csv", full.names = TRUE)
    if (length(available_files) == 0) {
      stop("在 ", base_dir, " 中找不到任何網絡指標檔案")
    }
    cat("找不到指定檔案:", metrics_file, "\n")
    cat("可用的指標檔案:\n")
    for (i in seq_along(available_files)) {
      cat(i, ":", basename(available_files[i]), "\n")
    }
    stop("請指定正確的 year_suffix 參數")
  }
  
  cat("載入網絡指標:", metrics_file, "\n")
  metrics_data <- read.csv(metrics_file, stringsAsFactors = FALSE)
  
  # 轉換日期欄位
  metrics_data$game_date <- as.Date(metrics_data$game_date)
  
  cat("成功載入", nrow(metrics_data), "筆網絡指標記錄\n")
  cat("涵蓋賽季:", paste(unique(metrics_data$season), collapse = ", "), "\n")
  cat("涵蓋賽季類型:", paste(unique(metrics_data$season_type), collapse = ", "), "\n")
  cat("涵蓋球隊:", length(unique(metrics_data$team)), "支\n")
  
  return(metrics_data)
}







# 執行批量分析
results <- batch_analyze_pass_networks(
  year_start = 2015,
  year_end = 2024,
  top_minutes_players = 5,
  min_pass = 0,
  season_types = c("Regular Season", "Playoffs"),
  pass_data = all_pass_data,
  player_data = player_game_data,
  player_attributes = all_player_attributes,
  verbose = TRUE
)

# 載入指標數據進行分析（修正路徑）
metrics_data <- load_batch_metrics(
  base_dir = "data/all_passes_per_game", 
  year_suffix = "2015_to_2024"
)

# 查看結果摘要
head(metrics_data)
summary(metrics_data)


