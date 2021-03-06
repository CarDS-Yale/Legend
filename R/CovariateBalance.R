# Copyright 2018 Observational Health Data Sciences and Informatics
#
# This file is part of Legend
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#' Compute covariate balance for each comparison
#'
#' @details
#' Compute covariate balance for each comparison. We don't compute balance for every TCO, as this
#' would be prohibitively large. Instead, we compute balance considering the entire target
#' and comparator cohort, so not removing subjects with prior outcomes. We do compute covariate balance
#' for every TCO for a small subset of covariates of interest (those used in the typical table 1).
#' Stores the results in a subfolder called 'balance'.
#'
#' @param indicationId   A string denoting the indicationId for which the covariate balance should be
#'                       computed.
#' @param outputFolder   Name of local folder to place results; make sure to use forward slashes (/)
#' @param maxCores       How many parallel cores should be used? If more cores are made available this
#'                       can speed up the analyses.
#'
#' @export
computeCovariateBalance <- function(indicationId = "Depression", outputFolder, maxCores) {
    ParallelLogger::logInfo("Computing covariate balance")
    indicationFolder <- file.path(outputFolder, indicationId)
    exposureSummary <- read.csv(file.path(indicationFolder,
                                          "pairedExposureSummaryFilteredBySize.csv"))
    balanceFolder <- file.path(indicationFolder, "balance")
    if (!file.exists(balanceFolder)) {
        dir.create(balanceFolder, recursive = TRUE)
    }
    # Using ITT study population, stratification, and matching arguments:
    cmAnalysisListFile <- system.file("settings",
                                      sprintf("cmAnalysisList%s.json", indicationId),
                                      package = "Legend")
    cmAnalysisList <- CohortMethod::loadCmAnalysisList(cmAnalysisListFile)
    studyPopArgs <- cmAnalysisList[[2]]$createStudyPopArgs
    stratifyByPsArgs <- cmAnalysisList[[2]]$stratifyByPsArgs
    cmAnalysisListFile <- system.file("settings",
                                      sprintf("cmAnalysisListAsym%s.json", indicationId),
                                      package = "Legend")
    cmAnalysisList <- CohortMethod::loadCmAnalysisList(cmAnalysisListFile)
    matchOnPsArgs <- cmAnalysisList[[2]]$matchOnPsArgs

    # Load restricted set of covariates to use for per-outcome balance:
    csvFile <- system.file("settings", "Table1Specs.csv", package = "Legend")
    table1Specs <- read.csv(csvFile)
    analysisIds <- table1Specs$analysisId[table1Specs$covariateIds == ""]
    covariateIds <- table1Specs$covariateIds[table1Specs$covariateIds != ""]
    covariateIds <- strsplit(as.character(covariateIds), ";")
    covariateIds <- do.call("c", covariateIds)
    covariateIds <- as.numeric(covariateIds)
    covarSubsetIds <- list(analysisIds = analysisIds, covariateIds = covariateIds)

    # Load outcomeModelReference:
    pathToRds <- file.path(outputFolder, indicationId, "cmOutput", "outcomeModelReference1.rds")
    outcomeModelReference1 <- readRDS(pathToRds)
    outcomeModelReference1 <- outcomeModelReference1[outcomeModelReference1$analysisId %in% 1:4, ]
    pathToRds <- file.path(outputFolder, indicationId, "cmOutput", "outcomeModelReference4.rds")
    if (file.exists(pathToRds)) {
        outcomeModelReference4 <- readRDS(pathToRds)
        outcomeModelReference4 <- outcomeModelReference4[outcomeModelReference4$analysisId %in% 1:4, ]
        outcomeModelReference <- rbind(outcomeModelReference1, outcomeModelReference4)
        rm(outcomeModelReference4)
    } else {
        outcomeModelReference <- outcomeModelReference1
    }
    rm(outcomeModelReference1)
    pathToCsv <- system.file("settings", "OutcomesOfInterest.csv", package = "Legend")
    outcomesOfInterest <- read.csv(pathToCsv, stringsAsFactors = FALSE)
    outcomesOfInterest <- outcomesOfInterest[outcomesOfInterest$indicationId == indicationId, ]
    outcomeModelReference <- outcomeModelReference[outcomeModelReference$outcomeId %in% outcomesOfInterest$cohortId, ]
    d <- merge(exposureSummary[, c("targetId", "comparatorId")],
               outcomeModelReference)
    d <- merge(d,
               data.frame(targetId = outcomeModelReference$comparatorId,
                          comparatorId = outcomeModelReference$targetId,
                          outcomeId = outcomeModelReference$outcomeId,
                          analysisId = outcomeModelReference$analysisId,
                          cmDataFolderCt = outcomeModelReference$cohortMethodDataFolder,
                          strataFileCt = outcomeModelReference$strataFile,
                          stringsAsFactors = FALSE),
               all.x = TRUE)
    rm(exposureSummary)
    rm(outcomeModelReference)
    if (indicationId == "Depression") {
        subgroupCovariateIds <- c(1998, 2998, 3998, 4998, 5998, 6998)
    } else if (indicationId == "Hypertension") {
        subgroupCovariateIds <- c(1998, 2998, 3998, 4998, 5998, 6998, 7998, 8998)
    }

    cluster <- ParallelLogger::makeCluster(numberOfThreads = min(6, maxCores))
    d <- split(d, paste(d$targetId, d$comparatorId))
    ParallelLogger::clusterApply(cluster = cluster,
                                 x = d,
                                 fun = Legend:::computeBalance,
                                 studyPopArgs = studyPopArgs,
                                 stratifyByPsArgs = stratifyByPsArgs,
                                 matchOnPsArgs = matchOnPsArgs,
                                 indicationFolder = indicationFolder,
                                 balanceFolder = balanceFolder,
                                 covarSubsetIds = covarSubsetIds,
                                 subgroupCovariateIds = subgroupCovariateIds)
    ParallelLogger::stopCluster(cluster)
}

computeBalance <- function(subset,
                           studyPopArgs,
                           stratifyByPsArgs,
                           matchOnPsArgs,
                           indicationFolder,
                           balanceFolder,
                           covarSubsetIds,
                           subgroupCovariateIds) {
    # subset <- d[[1]]
    ParallelLogger::logTrace("Computing balance for target ",
                             subset$targetId[1],
                             " and comparator ",
                             subset$comparatorId[1])
    cmDataFolder <- file.path(indicationFolder,
                              "cmOutput",
                              subset$cohortMethodDataFolder[1])
    cmData <- CohortMethod::loadCohortMethodData(cmDataFolder)
    if (!any(!is.na(subset$cmDataFolderCt))) {
        ParallelLogger::logDebug("Not computing balance for matching")
        # Matching was probably turned off
        cmDataCt <- NULL
        doMatching <- FALSE
    } else {
        cmDataCtFolder <- file.path(indicationFolder,
                                    "cmOutput",
                                    subset$cmDataFolderCt[!is.na(subset$cmDataFolderCt)][1])
        cmDataCt <- CohortMethod::loadCohortMethodData(cmDataCtFolder)
        # Reverse cohortMethodData objects have no covariate data. Add back in:
        cmDataCt$covariates <- cmData$covariates
        cmDataCt$covariateRef <- cmData$covariateRef
        doMatching <- TRUE
    }
    psFile <- file.path(indicationFolder, "cmOutput", subset$sharedPsFile[1])
    ps <- readRDS(psFile)
    # Compute balance when stratifying. Not specific to one outcome, so create hypothetical study
    # population --------
    studyPop <- CohortMethod::createStudyPopulation(cohortMethodData = cmData,
                                                    population = ps,
                                                    firstExposureOnly = studyPopArgs$firstExposureOnly,
                                                    restrictToCommonPeriod = studyPopArgs$restrictToCommonPeriod,
                                                    washoutPeriod = studyPopArgs$washoutPeriod,
                                                    removeDuplicateSubjects = studyPopArgs$removeDuplicateSubjects,
                                                    removeSubjectsWithPriorOutcome = studyPopArgs$removeSubjectsWithPriorOutcome,
                                                    priorOutcomeLookback = studyPopArgs$priorOutcomeLookback,
                                                    minDaysAtRisk = studyPopArgs$minDaysAtRisk,
                                                    riskWindowStart = studyPopArgs$riskWindowStart,
                                                    addExposureDaysToStart = studyPopArgs$addExposureDaysToStart,
                                                    riskWindowEnd = studyPopArgs$riskWindowEnd,
                                                    addExposureDaysToEnd = studyPopArgs$addExposureDaysToEnd,
                                                    censorAtNewRiskWindow = studyPopArgs$censorAtNewRiskWindow)
    stratifiedPop <- CohortMethod::stratifyByPs(population = studyPop,
                                                numberOfStrata = stratifyByPsArgs$numberOfStrata,
                                                baseSelection = stratifyByPsArgs$baseSelection)
    fileName <- file.path(balanceFolder, paste0("Bal_t",
                                                subset$targetId[1],
                                                "_c",
                                                subset$comparatorId[1],
                                                "_a2.rds"))
    if (!file.exists(fileName)) {
        ParallelLogger::logTrace("Creating stratified balance file " , fileName)
        balance <- CohortMethod::computeCovariateBalance(population = stratifiedPop,
                                                         cohortMethodData = cmData)
        saveRDS(balance, fileName)
    }

    if (doMatching) {
        # Compute balance when matching. Not specific to one outcome, so use hypothetical study population ----
        fileName <- file.path(balanceFolder, paste0("Bal_t",
                                                    subset$targetId[1],
                                                    "_c",
                                                    subset$comparatorId[1],
                                                    "_a4.rds"))
        if (!file.exists(fileName)) {
            ParallelLogger::logTrace("Creating matched balance file " , fileName)
            matchedPop <- CohortMethod::matchOnPs(population = studyPop,
                                                  caliper = matchOnPsArgs$caliper,
                                                  caliperScale = matchOnPsArgs$caliperScale,
                                                  maxRatio = matchOnPsArgs$maxRatio)
            if (nrow(matchedPop) == 0) {
                ParallelLogger::logDebug("No subjects left after matching")
            } else {
                balance <- CohortMethod::computeCovariateBalance(population = matchedPop,
                                                                 cohortMethodData = cmData)
                saveRDS(balance, fileName)
            }
        }

        # Matching is asymmetrical, so flip. Not specific to one outcome, so use hypothetical study population ----
        fileName <- file.path(balanceFolder, paste0("Bal_t",
                                                    subset$comparatorId[1],
                                                    "_c",
                                                    subset$targetId[1],
                                                    "_a4.rds"))
        if (!file.exists(fileName)) {
            ParallelLogger::logTrace("Creating matched balance file " , fileName)
            studyPopCt <- studyPop
            studyPopCt$treatment <- 1 - studyPopCt$treatment
            matchedPopCt <- CohortMethod::matchOnPs(population = studyPopCt,
                                                    caliper = matchOnPsArgs$caliper,
                                                    caliperScale = matchOnPsArgs$caliperScale,
                                                    maxRatio = matchOnPsArgs$maxRatio)
            if (nrow(matchedPopCt) == 0) {
                ParallelLogger::logDebug("No subjects left after matching")
            } else {
                balance <- CohortMethod::computeCovariateBalance(population = matchedPopCt,
                                                                 cohortMethodData = cmDataCt)
                saveRDS(balance, fileName)
            }
        }
    }
    # Compute balance within subgroups for stratification. Not specific to one outcome ----
    for (subgroupCovariateId in subgroupCovariateIds) {
        fileName <- file.path(balanceFolder, paste0("Bal_t",
                                                    subset$targetId[1],
                                                    "_c",
                                                    subset$comparatorId[1],
                                                    "_s",
                                                    subgroupCovariateId,
                                                    "_a2.rds"))
        if (!file.exists(fileName)) {
            subgroupSize <- ffbase::sum.ff(cmData$covariates$covariateId == subgroupCovariateId)
            if (subgroupSize > 1000) {
                # Check if completely separable:
                rowIds <- cmData$covariates$rowId[cmData$covariates$covariateId == subgroupCovariateId]
                strataSubPop <- stratifiedPop[stratifiedPop$rowId %in% ff::as.ram(rowIds), ]
                if (sum(strataSubPop$treatment == 1) != 0 &&
                    sum(strataSubPop$treatment == 0) != 0) {
                    ParallelLogger::logTrace("Creating subgroup balance file ", fileName)
                    balance <- CohortMethod::computeCovariateBalance(population = stratifiedPop,
                                                                     cohortMethodData = cmData,
                                                                     subgroupCovariateId = subgroupCovariateId)


                    saveRDS(balance, fileName)
                }
            }
        }
    }
    # Compute balance per outcome. Restrict to subset of covariates to limit space ----
    covariateIds <- cmData$covariateRef$covariateId[ffbase::`%in%`(cmData$covariateRef$analysisId,
                                                                   covarSubsetIds$analysisIds) | ffbase::`%in%`(cmData$covariateRef$covariateId,
                                                                                                                covarSubsetIds$covariateIds)]
    cmDataSubset <- cmData
    cmDataSubset$covariates <- cmData$covariates[ffbase::`%in%`(cmData$covariates$covariateId,
                                                                covariateIds), ]
    if (doMatching) {
        cmDataCtSubset <- cmDataCt
        cmDataCtSubset$covariates <- cmDataSubset$covariates
    }
    outcomeIds <- unique(subset$outcomeId)
    for (outcomeId in outcomeIds) {
        for (analysisId in unique(subset$analysisId)) {
            fileName <- file.path(balanceFolder, paste0("Bal_t",
                                                        subset$targetId[1],
                                                        "_c",
                                                        subset$comparatorId[1],
                                                        "_o",
                                                        outcomeId,
                                                        "_a",
                                                        analysisId,
                                                        ".rds"))
            if (!file.exists(fileName)) {
                ParallelLogger::logTrace("Creating outcome-specific balance file ", fileName)
                strataPopFile <- subset$strataFile[subset$outcomeId == outcomeId &
                                                       subset$analysisId == analysisId]
                strataPop <- readRDS(file.path(indicationFolder, "cmOutput", strataPopFile))
                if (nrow(strataPop) == 0) {
                    ParallelLogger::logDebug("Stratified population file ", strataPopFile, " has 0 rows")
                } else {
                    balance <- CohortMethod::computeCovariateBalance(population = strataPop,
                                                                     cohortMethodData = cmDataSubset)


                    saveRDS(balance, fileName)
                }
            }
            # See if reverse strata pop also exists (= matching)
            strataPopFile <- subset$strataFileCt[subset$outcomeId == outcomeId &
                                                     subset$analysisId == analysisId]
            if (!is.na(strataPopFile)) {
                fileName <- file.path(balanceFolder, paste0("Bal_t",
                                                            subset$comparatorId[1],
                                                            "_c",
                                                            subset$targetId[1],
                                                            "_o",
                                                            outcomeId,
                                                            "_a",
                                                            analysisId,
                                                            ".rds"))
                if (!file.exists(fileName)) {
                    ParallelLogger::logTrace("Creating outcome-specific balance file ", fileName)
                    strataPop <- readRDS(file.path(indicationFolder, "cmOutput", strataPopFile))
                    if (nrow(strataPop) == 0) {
                        ParallelLogger::logDebug("Stratified population file ", strataPopFile, " has 0 rows")
                    } else {
                        balance <- CohortMethod::computeCovariateBalance(population = strataPop,
                                                                         cohortMethodData = cmDataCtSubset)


                        saveRDS(balance, fileName)
                    }
                }
            }
        }
    }
    return(NULL)
}
