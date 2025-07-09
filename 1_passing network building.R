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

# 匯入球隊表現數據
import_team_performance <- function(performance_path = "data/performance_team") {
  cat("\n正在匯入球隊表現數據...\n")
  
  if (!dir.exists(performance_path)) stop("球隊表現資料夾不存在")
  
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

# 匯入球員逐場數據
import_player_game_data <- function(player_path = "data/performance_player_pergame") {
  cat("\n正在匯入球員逐場數據...\n")
  
  if (!dir.exists(player_path)) stop("球員表現資料夾不存在")
  
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

# 匯入團隊每場比賽統計數據
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

# 匯入所有NBA數據
import_all_nba_data <- function(performance_path = "data/performance_team",
                                player_path = "data/performance_player_pergame",
                                team_stats_file = "data/performance_team_pergame/all_seasons_all_games_team_stats.csv") {
  
  cat("=== NBA傳球網絡分析數據匯入開始 ===\n")
  result <- list()
  
  # 載入原有數據
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
  
  # 載入傳球數據
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
  
  # 載入球員屬性
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

# 篩選網絡分析用球員
filter_network_players <- function(data, season, team_abbr, date_start, date_end,
                                   filter_method = "traditional", min_games = 1, min_minutes = 15,
                                   top_minutes_players = NULL, verbose = FALSE) {
  
  original_locale <- Sys.getlocale("LC_TIME")
  Sys.setlocale("LC_TIME", "C")
  
  step1_data <- data %>%
    filter(SEASON == season) %>%
    mutate(parsed_date = as.Date(GAME_DATE, format = "%b %d, %Y"))
  
  Sys.setlocale("LC_TIME", original_locale)
  
  target_start <- as.Date(date_start)
  target_end <- as.Date(date_end)
  
  date_filtered <- step1_data %>%
    filter(!is.na(parsed_date), parsed_date >= target_start, parsed_date <= target_end)
  
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
    if (verbose) cat("在指定日期範圍內找不到", team_abbr, "隊球員的比賽記錄\n")
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
      filter(games_played >= min_games, avg_min >= min_minutes)
  } else if (filter_method == "top_minutes") {
    network_players <- player_summary %>% head(top_minutes_players)
  } else if (filter_method == "combined") {
    basic_filtered <- player_summary %>%
      filter(games_played >= min_games, avg_min >= min_minutes)
    network_players <- basic_filtered %>% head(top_minutes_players)
  }
  
  if (verbose && nrow(network_players) > 0) {
    cat("篩選出", nrow(network_players), "名球員用於網絡分析\n")
    cat("球員名單:", paste(network_players$PLAYER_NAME, collapse = ", "), "\n")
  }
  
  return(network_players)
}

# 建立傳球網絡
build_pass_network <- function(season_label, team_abbr, season_type = "Regular Season",
                               date_start = NULL, date_end = NULL, player_data = NULL,
                               pass_data = NULL, player_attributes = NULL, min_pass = 5,
                               filter_method = "traditional", min_games = 1, min_minutes = 15,
                               top_minutes_players = NULL, verbose = TRUE) {
  
  if (is.null(date_start) || is.null(date_end)) {
    stop("請提供 date_start 和 date_end 參數 (格式: 'YYYY-MM-DD')")
  }
  
  if (is.null(player_data) || is.null(pass_data) || is.null(player_attributes)) {
    stop("請提供 player_data, pass_data, player_attributes 參數")
  }
  
  if (filter_method %in% c("top_minutes", "combined") && is.null(top_minutes_players)) {
    stop("使用 top_minutes 或 combined 篩選方式時，請提供 top_minutes_players 參數")
  }
  
  if (verbose) {
    cat("=== 建立傳球網絡 ===\n")
    cat("賽季:", season_label, "| 球隊:", team_abbr, "| 日期:", date_start, "至", date_end, "\n")
    cat("篩選方式:", filter_method, "| 最少傳球:", min_pass, "\n")
  }
  
  filtered_players <- filter_network_players(
    data = player_data, season = season_label, team_abbr = team_abbr,
    date_start = date_start, date_end = date_end, filter_method = filter_method,
    min_games = min_games, min_minutes = min_minutes,
    top_minutes_players = top_minutes_players, verbose = verbose
  )
  
  if (nrow(filtered_players) == 0) stop("沒有符合篩選條件的球員")
  
  pass_edges <- pass_data
  season_player_attributes <- player_attributes %>% filter(SEASON == season_label)
  
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
    filter(SEASON_TYPE == season_type, TEAM_ABBREVIATION == team_abbr,
           GAME_DATE >= date_start, GAME_DATE <= date_end)
  
  if (nrow(filtered_edges) == 0) stop("在指定條件下沒有找到傳球數據")
  
  player_name_to_id <- season_player_attributes %>%
    select(id, DISPLAY_FIRST_LAST) %>%
    rename(PLAYER_ID = id, PLAYER_NAME = DISPLAY_FIRST_LAST)
  
  filtered_player_ids <- filtered_players %>%
    left_join(player_name_to_id, by = "PLAYER_NAME") %>%
    filter(!is.na(PLAYER_ID)) %>%
    pull(PLAYER_ID)
  
  if (length(filtered_player_ids) == 0) stop("無法匹配球員ID，請檢查球員姓名格式")
  
  network_edges <- filtered_edges %>%
    filter(PLAYER_ID %in% filtered_player_ids, PASS_TEAMMATE_PLAYER_ID %in% filtered_player_ids)
  
  if (nrow(network_edges) == 0) stop("篩選球員之間沒有傳球數據")
  
  pass_summary <- network_edges %>%
    group_by(PLAYER_ID, PASS_TEAMMATE_PLAYER_ID) %>%
    summarise(total_passes = sum(PASS), total_assists = sum(AST), .groups = "drop") %>%
    filter(total_passes >= min_pass)
  
  if (nrow(pass_summary) == 0) {
    stop(paste("沒有符合最少傳球次數條件的連結 (門檻:", min_pass, ")"))
  }
  
  valid_player_ids <- unique(c(pass_summary$PLAYER_ID, pass_summary$PASS_TEAMMATE_PLAYER_ID))
  network_player_attributes <- season_player_attributes %>% filter(id %in% valid_player_ids)
  
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
  
  # 儲存網絡屬性
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
    cat("網絡建構完成: 球員數", vcount(pass_network), "| 連結數", ecount(pass_network), 
        "| 總傳球", sum(E(pass_network)$total_passes), "| 總助攻", sum(E(pass_network)$total_assists), "\n")
  }
  
  return(pass_network)
}

# 繪製NBA傳球網絡
plot_pass_network <- function(network) {
  
  if (!is.igraph(network)) stop("network parameter must be an igraph object")
  if (vcount(network) == 0) stop("No nodes in the network")
  
  # 設定節點大小 (基於助攻數)
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
  
  # 設定邊寬度 (基於傳球數)
  if ("total_passes" %in% edge_attr_names(network)) {
    E(network)$width <- scales::rescale(E(network)$total_passes, to = c(1, 3))
  } else {
    E(network)$width <- 2
  }
  
  set.seed(123)
  layout <- layout_with_fr(network)
  
  # 取得網絡屬性
  team_abbr <- graph_attr(network, "team_abbr") %||% "TEAM"
  date_start <- graph_attr(network, "date_start") %||% ""
  date_end <- graph_attr(network, "date_end") %||% ""
  filter_method <- graph_attr(network, "filter_method") %||% ""
  min_pass <- graph_attr(network, "min_pass") %||% ""
  min_games <- graph_attr(network, "min_games") %||% NULL
  min_minutes <- graph_attr(network, "min_minutes") %||% NULL
  top_minutes_players <- graph_attr(network, "top_minutes_players") %||% NULL
  
  # 建立標題
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
  
  title_parts <- c(team_abbr)
  if (date_range != "") title_parts <- c(title_parts, date_range)
  if (filter_description != "") title_parts <- c(title_parts, filter_description)
  if (min_pass != "") title_parts <- c(title_parts, paste0("Min ", min_pass, " Passes"))
  
  main_title <- paste(title_parts, collapse = " | ")
  
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
  
  # 圖例
  if ("node_assists" %in% vertex_attr_names(network)) {
    max_assists <- max(V(network)$node_assists, na.rm = TRUE)
    min_assists <- min(V(network)$node_assists, na.rm = TRUE)
    
    legend("bottom", 
           legend = c(
             paste("Node Size: Assists (", min_assists, "-", max_assists, ")"),
             paste("Edge Width: Passes (", min(E(network)$total_passes), "-", max(E(network)$total_passes), ")")
           ),
           pch = c(21, NA), lty = c(NA, 1), lwd = c(NA, 3),
           pt.bg = "skyblue", pt.cex = c(1.5, NA),
           col = c("black", adjustcolor("grey30", alpha.f = 0.6)),
           bty = "o", bg = "white", box.col = "gray50", box.lwd = 1,
           cex = 0.8, horiz = TRUE, xpd = TRUE, inset = c(0, -0.15)
    )
  }
  
  par(mar = c(5, 4, 4, 2) + 0.1)
  
  # 網絡統計
  cat("\n=== 網絡統計 ===\n")
  cat("球員數:", vcount(network), "| 連結數:", ecount(network), "\n")
  if ("total_passes" %in% edge_attr_names(network)) {
    cat("總傳球:", sum(E(network)$total_passes), "| 平均傳球:", round(mean(E(network)$total_passes), 1), "\n")
  }
  if ("node_assists" %in% vertex_attr_names(network)) {
    cat("總助攻:", sum(V(network)$node_assists), "\n")
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



# 建立三種網絡
network1 <- build_pass_network(
  season_label = "2024-25",
  team_abbr = "DAL",
  date_start = "2024-12-01",
  date_end = "2024-12-31", 
  player_data = player_game_data,
  filter_method = "traditional",
  min_games = 5,
  min_minutes = 20
)

network2 <- build_pass_network(
  season_label = "2024-25",
  team_abbr = "DAL",
  date_start = "2024-12-23", 
  date_end = "2024-12-23",
  player_data = player_game_data,
  min_pass = 0,
  filter_method = "top_minutes",
  top_minutes_players = 5
)

network3 <- build_pass_network(
  season_label = "2024-25",
  team_abbr = "DAL", 
  date_start = "2024-12-01",
  date_end = "2024-12-31",
  player_data = player_game_data,
  min_pass = 0,
  filter_method = "combined",
  min_games = 3,
  min_minutes = 15,
  top_minutes_players = 10
)

# 3. 依序繪製網絡
cat("\n=== 繪製網絡圖 ===\n")

cat("\n--- Network 1: Traditional Filter ---\n")
plot_pass_network(network1)

cat("\n--- Network 2: Top Minutes ---\n")
plot_pass_network(network2)

cat("\n--- Network 3: Combined Filter ---\n")
plot_pass_network(network3)

cat("\n=== 分析完成 ===\n")

