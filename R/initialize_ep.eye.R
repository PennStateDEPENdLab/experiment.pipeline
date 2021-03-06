#' generic function for initializing ep.eye object and performing basic internal checks on the eye data, while remaining agnostic to task/behavior structure.
#'
#' This includes validation of very basic data quality (large variance in gaze distribution, excessive blinks, large jumps in eye position, etc).
#' TODO: include functionality for logging of successes, warnings, failures. This will probably involve a trycatch statement that could handle a potentially large number of issues. We'll have to see how complicated it gets by balancing flexibility with parsimony. Tend to prefer flexibility if the package allows user-side functionality to be parsimonious :)
#' TODO: perhaps even store key variables (e.g. some measure of pupil fluctuation, or saccade velocity/acceleration) from prior subjects in separate circumscribed csv (which values get appended to) and plot distributions for every new subject. This would be akin to constructing a sort of empirical null distribution and performing informal (visual)"hypothesis tests" where we would hope certain variables in a given subject are not "significantly different" than the group distribution.
#' @param eye raw eye object pulled directly from the .edf file using read_edf(). Must be a list with expected_edf_fields c("raw", "sacc", "fix", "blinks", "msg", "input", "button", "info", "asc_file", "edf_file").


initialize_ep.eye <- function(eye, config) {#, c. = 2) {

  if (class(eye) != "list") { stop("Something went wrong: initialize_eye requires list input.") }

  # cat("\n--------------\n", c., " Initialize eye object:\n--------------\n")
  cat("\n--------------\n2. Initialize eye object:\n--------------\n")

  ### 2.1 make sure all names are present
  expected_edf_fields <- c("raw", "sacc", "fix", "blinks", "msg", "input", "button", "info", "asc_file", "edf_file")
  stopifnot(all(expected_edf_fields %in% names(eye)))
  cat("- 2.1 Check expected fields: COMPLETE\n")

  ### 2.2 initialize basic eye object structure
  eout <- list(raw = eye$raw,
               msg = eye$msg,
               gaze = list(downsample = data.table(),
                           sacc = as.data.table(eye$sacc) %>% mutate(saccn = 1:nrow(.)),
                           fix = as.data.table(eye$fix) %>% mutate(fixn = 1:nrow(.)),
                           blink = as.data.table(eye$blinks) %>% mutate(blinkn = 1:nrow(.))),
               pupil = list(
                 downsample = data.table(),
                 # fix = data.table(),
                 # trial = data.table(),
                 # event = data.table(),
                 preprocessed = data.table()),
               # summary = list(counts = data.table(),
               #                sacc = data.table(),
               #                fix = data.table(),
               #                blink = data.table(),
               #                pupil = data.table()
               #),
               metadata = suppress_warnings(split(t(eye$info),f = colnames(eye$info)) %>% lapply(., function(x) {
                 if (x %in% c("TRUE", "FALSE")){
                   as.logical(x)} else if(!is.na(as.numeric(x))){
                     as.numeric(x)} else {x}
               } ))
  )

  eout[["metadata"]][["edf_file"]] <- eye$edf_file

  class(eout) <- c(class(eye), "ep.eye") #tag with ep.eye class

  cat("- 2.2 Initialize ep.eye list structure: COMPLETE\n")




  ### 2.3 document entire recording session length (if this is very different from BAU this should get flagged later)
  mintime <- min(eout$raw$time)
  maxtime <- max(eout$raw$time)
  all_time <- seq(mintime,maxtime,1)

  # store overall time for later
  tt <- maxtime-mintime
  eout$metadata$recording_time <- tt_sec <- tt/eout$metadata$sample.rate

  time_english <- lubridate::seconds_to_period(tt_sec)
  cat("- 2.3 Document recording session length (", time_english,"): COMPLETE\n", sep = "")

  ### 2.4 check for continuity in timestamp on raw data

  # not sure what to do with the open gaps atm, but the fact that are for subsequent chunks of time makes me think this has to do with the structure fo the task rather than noise.

  if(all(all_time %in%  eout$raw$time)){
    missing_measurements <- 0 #if everything stricly accounted for (i.e. every sampling period from beginning to end has a measurement... in my experience this is unlikely, esp if between trials the eyetracker is told to stop/start sampling)
  } else{
    #store the gaps for later
    mm <- which(!all_time %in% eout$raw$time)  # missing measurements.

    ###### deprecated: too cumbersome to store all missing measurements, and have instead elected to summarise in a compact DT below. Given how these missing events are generated, we know that they are consecutive events of missing data.
    # eout$metadata[["missing_measurements"]][["raw_events"]] <- mms <- split(mm, cumsum(c(1, diff(mm) != 1))) #contains all timestamps in between session start and end time that are missing blocked by consecutive timestamps. will likely want to dump before returning output
    # eout$metadata[["missing_measurements"]][["cumulative_byevent"]] <- lapply(mms, function(x) {length(x)}) %>% do.call(c,.) %>% as.numeric() # vector containing the length of each consecutive missing timestamp block.
    # eout$metadata[["missing_measurements"]][["summary"]] <-  data.table("start" = lapply(mms, function(x) {min(x)}) %>% do.call(c,.),
    #                                                                     "end" = lapply(mms, function(x) {max(x)}) %>% do.call(c,.),
    #                                                                     # "length" = eout$metadata[["missing_measurements"]][["cumulative_byevent"]])

    # much simplified.
    mms <- split(mm, cumsum(c(1, diff(mm) != 1))) # rather than exporting as metadata (too cumbersome) store for input into summary DT.
    mmls <- lapply(mms, function(x) {length(x)}) %>% do.call(c,.) %>% as.numeric() # same as above, just store in summary.
    eout$metadata[["missing_measurements"]] <-  data.table("start" = lapply(mms, function(x) {min(x)}) %>% do.call(c,.),
                                                           "end" = lapply(mms, function(x) {max(x)}) %>% do.call(c,.),
                                                           "length" = mmls)

    # x <- eout$metadata[["missing_measurements"]] %>% tibble()
    #
    # for(i in 1:nrow(x)){
    #   s <- x[i,]
    # }

    #abandon time_limits argument for now.
    # # convert to expected measurement range based on sampling rate
    # samp_range <- c(time_limits[1]*eout$metadata$sample.rate - time_limits[2]*eout$metadata$sample.rate,
    #                 time_limits[1]*eout$metadata$sample.rate + time_limits[2]*eout$metadata$sample.rate)
  }

  cat("- 2.4 Document missing measurements and pad missing measurements: COMPLETE\n")


  # ### for large chunks of missing data, (e.g. if tracker turned off between trials), important to flag "recording chunks" of complete data
  # gen_run_num <- function(x){
  #   rl <- rle(is.na(x))
  #   lst <- split(x, rep(cumsum(c(TRUE, rl$values[-length(rl$values)])), rl$lengths))
  #   runvec <- c()
  #   for(i in 1:length(lst)){
  #     runvec <- c(runvec, rep(i, length(lst[[i]])))
  #   }
  #
  #   runvec <- ifelse(is.na(x), NA, runvec)
  #   return(runvec)
  # }
  # eout$raw



  ### 5. check for continuity in events

  if(all(unique(eout$raw$eventn) == seq(min(unique(eout$raw$eventn)), max(unique(eout$raw$eventn)),1))){
    # confirmed that unique sorts in order they appear in the array. E.g. y <- c(1,1,3,3,2,3); unique(y) : [1] 1 3 2.
    # will therefor check for skipped events and the ordering.
    cat("- 2.5 Confirm raw event continuity: COMPLETE\n")
  } else{
    cat("- 2.5 Confirm raw event continuity: FAIL\n")
  }


  ### 6. check for matching between raw timestamps and saccades, fixations, blinks ("gaze events")

  gevs <- c("sacc", "fix", "blink")
  issues <- list()

  cat("- 2.6 Verify correspondence of gaze events and raw data:\n")

  # will end up tagging raw data with gev numbers
  eout$raw <- eout$raw %>% mutate(saccn = rep(0, length(eout$raw$time)),
                                  fixn = rep(0, length(eout$raw$time)),
                                  blinkn = rep(0, length(eout$raw$time)))

  for(i in gevs){
    step <- paste0("2.6.", which(gevs == i))
    cat("-- ",step, " ", i, ":\n", sep = "")
    step <- paste0(step, ".1")
    issues[[i]] <- list()

    # pull gaze event data
    gev <- eout$gaze[[i]]


    ## 6.i.1. event sequencing same between gaze metric and raw data? If not, this would mean that not a single gaze event happened during this trial, which could be a bit fishy.

    #may want to play with this later, but for now flag in list of issues that for these events there was no evidence of a certain event (not necessarily a sign of bad data)
    issues[[i]][["event_without_ev"]] <- which(!unique(eout$raw$eventn) %in% unique(gev$eventn))

    if(!all(unique(gev$eventn) == unique(eout$raw$eventn))){
      cat("--- ",step, " Search for events without gaze events: WARNING (",length(issues[[i]][["event_without_ev"]]),")\n", sep = "")
    } else{
      cat("---",step, " Search for events without gaze events: COMPLETE\n")
    }


    ## 6.i.2. Two nit-picky checks: confirm timestamps are equal and present in raw and gev data. confirm same event numbering between raw and gev data. Then tag raw data with event number.
    # This essentially checks that correspondence between raw and extracted gaze events are exactly as expected.
    # in an ideal world these all run without issue, though even very minuscule mismatches will get flagged here. If there becomes some consistency in mismatches, perhaps it's worth doing some investigating.

    step_26i2 <- paste0("2.6.", which(gevs == i), ".2")

    counts_26i2 <- list()#  "etime_mismatch" , "event_mismatch")
    # since this loops over typically thousands of gaze events, this is the most computationally intensive part of the initialization script.
    for (j in 1:nrow(gev)) {
      # print(j)
      ev <- gev[j,]
      etimes <- seq(ev$stime, ev$etime,1)
      ## pull from raw data
      r <- eout$raw[eout$raw$time %in% etimes,]

      # check 1: confirm timestamps are equal and present in raw and gev data
      if(#!(length(r$time) == length(etimes)) | #if number of measurements dont match
        !all(r$time == etimes)    # this supersedes the above, forcing number of measurements to be exact and have timestamps be strictly equal
      ){
        counts_26i2[["etime_mismatch"]] <- c(counts_26i2[["etime_mismatch"]], j)
      }

      #check 2: confirm same event numbering between raw and gev data.
      if(!ev$eventn == unique(r$eventn)){
        b_mismatch <- data.table("gev" = i, "gev_num" = j, "ev_event" = ev$eventn, "raw_num" = unique(r$eventn))
        counts_26i2[["event_mismatch"]] <- rbind(counts_26i2[["event_mismatch"]], b_mismatch)
      }

      #tag raw data with event number
      eout$raw[which(eout$raw$time %in% etimes), paste0(i,"n")] <- j
    }

    # all gevs should be represented in the raw data now +1 (0 represents no event)
    if(length(unique(as.matrix(eout$raw[, paste0(i,"n")]))) != nrow(gev) +1){
      counts_26i2[["raw_tag_gevs"]] <- length(unique(as.matrix(eout$raw[, paste0(i,"n")])))
    }


    if(length(counts_26i2) != 0){
      issues[[i]][["raw_gev_mismatches"]] <- counts_26i2
      cat("--- ",step_26i2, " Check timing mismatches between raw gaze data and extracted gaze events: WARNING (look in metadata for timing issues)\n", sep = "")
    } else { #perfect match, and all gev tagging worked just fine.
      cat("--- ",step_26i2, " Check timing mismatches between raw gaze data and extracted gaze events: COMPLETE\n", sep = "")
    }

  }

  eout$metadata[["gev_issues"]] <- issues

  # names(eout$metadata)
  # eout$metada[which(names(eout$metada) != "missing_measurements")]

  ### 7. Confirm that tagging raw data with GEV numbers successful

  gev_tag_check <- 0

  if (!all(paste0(gevs, "n") %in% names(eout$raw))) {
    gev_tag_check <- 1
  } else{ # meaning columns are existent
    for(i in gevs){
      # i <- "sacc"
      i.n <- paste0(i, "n")
      rawtag <- unique(eout$raw[[i.n]])

      ## need to remove timestamps from raw data with no gev (0) for proper matching
      rawtag<-rawtag[which(rawtag > 0)]

      # extract gev numbers as they appear in the gaze field of the ep.eye list.
      cnum <- which(names(eout$gaze[[i]]) == i.n)
      gevnums <- eout$gaze[[i]][ ,..cnum] %>% as.matrix() %>% as.numeric()

      if(!all(rawtag %in% gevnums)){gev_tag_check <- 2}
    }
  }

  if(gev_tag_check == 0){#success
    cat("- 2.7 Confirm accurate tagging of raw data with gaze event numbers: COMPLETE\n")
  } else{
    cat("- 2.7 Confirm accurate tagging of raw data with gaze event numbers: WARNING (",gev_tag_check,")\n", sep = "")
  }

  ### 8. Finish up tidying of raw DT: 1) store messages with no timestamp 2) verify uselessness of cr.info column 3) merge with messages, and "back-check" for errors.

  cat("- 2.8 Finish raw DT tidying:\n", sep = "")

  # 8.1 store messages with no timestamp match in raw data (collected between trials with no corresponding measurements).
  # In my (neighborhood) checks these have to do with calibration parameters, display coords, etc. For most users this will not be very helpful.
  # N.B. however, if the user passes important information before turning the tracker on (as in the sorting mushrooms data), it will be important to allow for users to move messages in the interstitial spaces between recordings to the beginning of a trial/event. Later will include this in the YAML parsing framework.
  btw_tr <- eye$msg %>% anti_join(eout$raw, by = "time") %>% data.table()
  if(nrow(btw_tr) == 0){
    cat("-- 2.8.1 Between-trial message storage: COMPLETE (EMPTY)\n", sep = "")
  } else{
    eout$metadata[["btw_tr_msg"]] <- btw_tr
    cat("-- 2.8.1 Between-trial message storage: COMPLETE (NON-EMPTY)\n", sep = "")
  }

  # 8.2 drop cr.info column
  cr <- unique(eout$raw$cr.info)
  if(length(cr) == 1 & cr == "..."){
    eout$raw <- eout$raw %>% select(-cr.info)
    cat("-- 2.8.2 Drop cr.info in raw data: COMPLETE\n", sep = "")
  } else{ cat("-- 2.8.2 Retain cr.info in raw data: COMPLETE (",paste0(cr, collapse = ","),")\n", sep = "")}

  # 8.3 merge messages to raw data.
  # N.B. the left_join means that between trial messages will not be copied over but rather are stored in metadata if between trial messages are of interest. Since there is no corresponding measurements of gaze/pupil in the raw data there is nowhere in the raw time series to place these relatively unhelpful messages.
  # N.B. Under the current set-up this operation will increase the number of rows if multiple messages are passed simultaneously. At a later point, one could change this format with the yaml config file under $definitions$eye$coincident_msg.
  eout$raw <- eout$raw %>% left_join( dplyr::filter(eye$msg, !text %in% unique(btw_tr$text)), by = c("eventn", "time")) %>% rename(`et.msg` = `text`)  %>% mutate(et.msg = ifelse(is.na(et.msg), ".", et.msg)) %>% data.table()

  # important to back-translate to original messages due to the use of left_join.
  umsg <- unique(eout$raw$et.msg)[which(unique(eout$raw$et.msg) != ".")] #unique messages in the final output.

  if(nrow(btw_tr) != 0){
    umsg_edf <- unique(eye$msg$text) # unadulterated, right off the eyetracker.
    umsg_orig <- umsg_edf[which(!umsg_edf %in% unique(btw_tr$text))] # make sure to eliminate between-trial messages and just grab messages that are passed while recording.

    # length(umsg) + length(unique(btw_tr$text)) == length(unique(eye$msg$text))
  } else{
    umsg_orig <- eye$msg$text # no btwn-trial messages to filter out.
  }

  if(all(umsg %in% umsg_orig)){
    cat("-- 2.8.3 Merge raw gaze data with eyetracker messages, with successful back-translate: COMPLETE\n", sep = "")
  } else{ # if any mismatch between what is contained in raw data and original message structure, print error and do some digging.

    miss_msgs <- umsg[!umsg %in% umsg_orig]
    eout$metadata[["missing_messages_raw"]] <- miss_msgs

    mmsgs_stamped <- eye$msg[which(eye$msg$text %in% miss_msgs), ]
    for(i in 1:nrow(mmsgs_stamped)){
      mstamp <- mmsgs_stamped[i,2] #grab missing timestamp.
      mstamp %in% mm
      mm
    }


    cat("-- 2.8.3 Merge raw gaze data with eyetracker messages, with successful back-translate: WARNING: errors in this step have not been fully vetted. \n", sep = "")
  }


  ### 9 Shift timestamps to 0 start point
  dt <- "- 2.9 Shift timestamps to 0 start point:"
  eout <- shift_eye_timing(eout,dt)


  cat("\n")
  return(eout)
}

