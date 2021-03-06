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

# Some internal diagnostics to check the results of the analyses.

# Study size -----------------------------------------------------------------------------------------------
indicationFolder <- file.path(outputFolder, indicationId)
diagnosticsFolder <- file.path(indicationFolder, "internalDiagnostics")
if (!file.exists(diagnosticsFolder)) {
    dir.create(diagnosticsFolder)
}
exposureSummary <- read.csv(file.path(indicationFolder, "pairedExposureSummaryFilteredBySize.csv"))
exposureSummary$totalPairedPersons <- exposureSummary$targetPairedPersons + exposureSummary$comparatorPairedPersons
exposureSummary <- exposureSummary[order(-exposureSummary$totalPairedPersons), ]
exposureSummary$order <- seq(nrow(exposureSummary))
d <- rbind(data.frame(order = exposureSummary$order,
                      subjects = exposureSummary$targetPairedPersons,
                      cohort = "target"),
           data.frame(order = exposureSummary$order,
                      subjects = exposureSummary$comparatorPairedPersons,
                      cohort = "comparator"))

library(ggplot2)
plot <- ggplot(d, aes(x = order, y = subjects, color = cohort, fill = cohort)) +
    geom_bar(stat = "identity", width = 1) +
    scale_fill_manual(values = c(rgb(0.8, 0, 0, alpha = 0.5), rgb(0, 0, 0.8, alpha = 0.5))) +
    scale_color_manual(values = c(rgb(0.8, 0, 0, alpha = 0.5), rgb(0, 0, 0.8, alpha = 0.5))) +
    scale_x_continuous("Comparisons") +
    scale_y_continuous("Number of subjects")
ggsave(filename = file.path(diagnosticsFolder, "comparisonSizes.png"), plot = plot, width = 12, height = 5, dpi = 300)

tCohorts <- aggregate(targetPersons ~ targetId + targetName, exposureSummary, max)
cCohorts <- aggregate(comparatorPersons ~ comparatorId + comparatorName, exposureSummary, max)
colnames(tCohorts) <- c("exposureId", "exposureName", "exposureSubjects")
colnames(cCohorts) <- c("exposureId", "exposureName", "exposureSubjects")
cohorts <- rbind(tCohorts, cCohorts)
cohorts <- unique(cohorts)
cohorts <- cohorts[order(cohorts$exposureId), ]

tcos <- readRDS("s:/temp/tcos.rds")
x <- sapply(tcos, function(x) length(x$outcomeIds))
sum(x)
# Overview of PS plots --------------------------------------------------------------------------------------
indicationFolder <- file.path(outputFolder, indicationId)
diagnosticsFolder <- file.path(indicationFolder, "internalDiagnostics")
if (!file.exists(diagnosticsFolder)) {
    dir.create(diagnosticsFolder)
}
cmFolder <- file.path(indicationFolder, "cmOutput")
exposureSummary <- read.csv(file.path(indicationFolder, "pairedExposureSummaryFilteredBySize.csv"))
outcomeModelReference <- readRDS(file.path(indicationFolder,
                                           "cmOutput",
                                           "outcomeModelReference.rds"))

i <- 22

preparePlot <- function(i, exposureSummary, outcomeModelReference) {
    targetId <- exposureSummary$targetId[i]
    comparatorId <- exposureSummary$comparatorId[i]
    idx <- outcomeModelReference$targetId == targetId & outcomeModelReference$comparatorId == comparatorId &
        outcomeModelReference$analysisId == 1
    psFileName <- outcomeModelReference$sharedPsFile[idx][1]
    if (file.exists(file.path(cmFolder, psFileName))) {
        ps <- readRDS(file.path(cmFolder, psFileName))
        if (min(ps$propensityScore) < max(ps$propensityScore)) {
            ps <- CohortMethod:::computePreferenceScore(ps)
            d1 <- density(ps$preferenceScore[ps$treatment == 1], from = 0, to = 1, n = 100)
            d0 <- density(ps$preferenceScore[ps$treatment == 0], from = 0, to = 1, n = 100)
            d <- data.frame(x = c(d1$x, d0$x), y = c(d1$y, d0$y), treatment = c(rep(1, length(d1$x)),
                                                                                rep(0, length(d0$x))))
            d$y <- d$y/max(d$y)
            d$targetId <- targetId
            d$targetName <- as.character(exposureSummary$targetName[i])
            d$comparatorId <- comparatorId
            d$comparatorName <- as.character(exposureSummary$comparatorName[i])
            result <- d
            d$x <- 1 - d$x
            d$treatment <- 1 - d$treatment
            d$targetId <- comparatorId
            d$targetName <- as.character(exposureSummary$comparatorName[i])
            d$comparatorId <- targetId
            d$comparatorName <- as.character(exposureSummary$targetName[i])
            result <- rbind(result, d)
            return(result)
        }
    }
    return(NULL)
}

data <- plyr::llply(1:nrow(exposureSummary),
                    preparePlot,
                    exposureSummary = exposureSummary,
                    outcomeModelReference = outcomeModelReference,
                    .progress = "text")
data <- do.call("rbind", data)
saveRDS(data, file.path(diagnosticsFolder, "ps.rds"))

plotAllPs <- function(data, fileName) {
    data$GROUP <- "Target"
    data$GROUP[data$treatment == 0] <- "Comparator"
    data$GROUP <- factor(data$GROUP, levels = c("Target", "Comparator"))
    library(ggplot2)
    plot <- ggplot(data, aes(x = x, y = y, color = GROUP, group = GROUP, fill = GROUP)) +
        geom_density(stat = "identity") +
        scale_fill_manual(values = c(rgb(0.8, 0, 0, alpha = 0.5), rgb(0, 0, 0.8, alpha = 0.5))) +
        scale_color_manual(values = c(rgb(0.8, 0, 0, alpha = 0.5), rgb(0, 0, 0.8, alpha = 0.5))) +
        scale_x_continuous("Preference score", limits = c(0, 1)) +
        scale_y_continuous("Density") +
        facet_grid(targetName ~ comparatorName) +
        theme(legend.title = element_blank(),
              axis.title.x = element_blank(),
              axis.text.x = element_blank(),
              axis.ticks.x = element_blank(),
              axis.title.y = element_blank(),
              axis.text.y = element_blank(),
              axis.ticks.y = element_blank(),
              panel.grid.major = element_blank(),
              panel.grid.minor = element_blank(),
              strip.text.x = element_text(size = 8, angle = 90, vjust = 0),
              strip.text.y = element_text(size = 8, angle = 0, hjust = 0),
              panel.spacing = unit(0.1, "lines"),
              legend.position = "none")
    ggsave(plot = plot, filename = fileName, width = 15, height = 9, dpi = 500)
}
if (indicationId == "Hypertension") {
    pathToCsv <- system.file("settings", "ExposuresOfInterest.csv", package = "Legend")
    exposuresOfInterest <- read.csv(pathToCsv)
    exposuresOfInterest <- exposuresOfInterest[exposuresOfInterest$indicationId == indicationId, ]
    exposureCombis <- read.csv(file.path(indicationFolder, "exposureCombis.csv"))
    # exposureCombis$type <- exposuresOfInterest$type[match(exposureCombis$exposureId1,
    # exposuresOfInterest$cohortId)]
    exposureTypes <- exposuresOfInterest[, c("cohortId", "type")]
    exposureTypes <- rbind(exposureTypes, data.frame(cohortId = exposureCombis$cohortDefinitionId,
                                                     type = exposureCombis$exposureType))
    dataDrugs <- data[data$targetId %in% exposureTypes$cohortId[exposureTypes$type == "Drug"], ]
    dataDrugClasses <- data[data$targetId %in% exposureTypes$cohortId[exposureTypes$type == "Drug class"] &
                                data$comparatorId %in% exposureTypes$cohortId[exposureTypes$type == "Drug class"], ]
    dataDrugMajorClasses <- data[data$targetId %in% exposureTypes$cohortId[exposureTypes$type == "Drug major class"] &
                                     data$comparatorId %in% exposureTypes$cohortId[exposureTypes$type == "Drug major class"], ]
    plotAllPs(dataDrugs, file.path(diagnosticsFolder, "allPsDrugLevel.png"))
    plotAllPs(dataDrugClasses, file.path(diagnosticsFolder, "allPsClassLevel.png"))
    plotAllPs(dataDrugMajorClasses, file.path(diagnosticsFolder, "allPsMajorClassLevel.png"))
} else {
    pathToCsv <- system.file("settings", "ExposuresOfInterest.csv", package = "Legend")
    exposuresOfInterest <- read.csv(pathToCsv)
    exposuresOfInterest <- exposuresOfInterest[exposuresOfInterest$indicationId == indicationId, ]
    exposureTypes <- exposuresOfInterest[, c("cohortId", "type")]
    dataDrugs <- data[data$targetId %in% exposureTypes$cohortId[exposureTypes$type != "Drug class"] &
                          data$comparatorId %in% exposureTypes$cohortId[exposureTypes$type != "Drug class"], ]
    dataDrugClasses <- data[data$targetId %in% exposureTypes$cohortId[exposureTypes$type == "Drug class"] &
                                data$comparatorId %in% exposureTypes$cohortId[exposureTypes$type == "Drug class"], ]
    plotAllPs(dataDrugs, file.path(diagnosticsFolder, "allPsDrugLevel.png"))
    plotAllPs(dataDrugClasses, file.path(diagnosticsFolder, "allPsClassLevel.png"))

}




# Calibration plots
# -----------------------------------------------------------------------------------
indicationFolder <- file.path(outputFolder, indicationId)
diagnosticsFolder <- file.path(indicationFolder, "internalDiagnostics")
if (!file.exists(diagnosticsFolder)) {
    dir.create(diagnosticsFolder)
}
calibrationFolder <- file.path(diagnosticsFolder, "calibration")
if (!file.exists(calibrationFolder)) {
    dir.create(calibrationFolder)
}

indicationFolder <- file.path(outputFolder, indicationId)
exposureSummary <- read.csv(file.path(indicationFolder, "pairedExposureSummaryFilteredBySize.csv"))
analysesSum <- read.csv(file.path(indicationFolder, "analysisSummary.csv"))
pathToCsv <- system.file("settings", "NegativeControls.csv", package = "Legend")
negativeControls <- read.csv(pathToCsv)
negativeControlIds <- negativeControls$cohortId
signalInjectionSum <- read.csv(file.path(indicationFolder, "signalInjectionSummary.csv"))
sample <- 1:nrow(exposureSummary)
sample <- sample(nrow(exposureSummary), 100, replace = FALSE)
for (i in sample) {
    targetId <- exposureSummary$targetId[i]
    comparatorId <- exposureSummary$comparatorId[i]
    targetName <- exposureSummary$targetName[i]
    comparatorName <- exposureSummary$comparatorName[i]
    for (analysisId in unique(analysesSum$analysisId)) {
        estimates <- analysesSum[analysesSum$analysisId == analysisId & analysesSum$targetId == targetId &
                                     analysesSum$comparatorId == comparatorId, ]

        negControls <- estimates[estimates$outcomeId %in% negativeControlIds, ]
        fileName <- file.path(calibrationFolder, paste0("negControls_a",
                                                        analysisId,
                                                        "_t",
                                                        targetId,
                                                        "_c",
                                                        comparatorId,
                                                        ".png"))
        title <- paste(targetName, "vs.", comparatorName, "- analysis ", analysisId)
        EmpiricalCalibration::plotCalibrationEffect(logRrNegatives = negControls$logRr,
                                                    seLogRrNegatives = negControls$seLogRr,
                                                    title = title,
                                                    xLabel = "Hazard ratio",
                                                    fileName = fileName)
        fileName <- file.path(calibrationFolder, paste0("negControls_a",
                                                        analysisId,
                                                        "_t",
                                                        comparatorId,
                                                        "_c",
                                                        targetId,
                                                        ".png"))
        title <- paste(comparatorName, "vs.", targetName, "- analysis ", analysisId)
        EmpiricalCalibration::plotCalibrationEffect(logRrNegatives = -negControls$logRr,
                                                    seLogRrNegatives = negControls$seLogRr,
                                                    title = title,
                                                    xLabel = "Hazard ratio",
                                                    fileName = fileName)

        injectedSignals <- signalInjectionSum[signalInjectionSum$exposureId == targetId & signalInjectionSum$injectedOutcomes !=
                                                  0, ]
        negativeControlIdSubsets <- unique(injectedSignals$outcomeId)
        injectedSignals <- data.frame(outcomeId = injectedSignals$newOutcomeId,
                                      trueLogRr = log(injectedSignals$targetEffectSize))
        negativeControls <- data.frame(outcomeId = negativeControlIds, trueLogRr = 0)
        data <- rbind(injectedSignals, negativeControls)
        data <- merge(data, estimates[, c("outcomeId", "logRr", "seLogRr")])
        if (length(unique(data$trueLogRr)) > 1) {
            fileName <- file.path(calibrationFolder, paste0("negPosControls_a",
                                                            analysisId,
                                                            "_t",
                                                            targetId,
                                                            "_c",
                                                            comparatorId,
                                                            ".png"))
            title <- paste(targetName, "vs.", comparatorName, "- analysis ", analysisId)
            EmpiricalCalibration::plotCiCalibrationEffect(logRr = data$logRr,
                                                          seLogRr = data$seLogRr,
                                                          trueLogRr = data$trueLogRr,
                                                          title = title,
                                                          xLabel = "Hazard ratio",
                                                          fileName = fileName)

        }

        injectedSignals <- signalInjectionSum[signalInjectionSum$exposureId == comparatorId & signalInjectionSum$injectedOutcomes !=
                                                  0, ]
        negativeControlIdSubsets <- unique(injectedSignals$outcomeId)
        injectedSignals <- data.frame(outcomeId = injectedSignals$newOutcomeId,
                                      trueLogRr = log(injectedSignals$targetEffectSize))
        negativeControls <- data.frame(outcomeId = negativeControlIds,
                                       trueLogRr = rep(0, length(negativeControlIds)))
        data <- rbind(injectedSignals, negativeControls)
        data <- merge(data, estimates[, c("outcomeId", "logRr", "seLogRr")])
        if (length(unique(data$trueLogRr)) > 1) {
            fileName <- file.path(calibrationFolder, paste0("negPosControls_a",
                                                            analysisId,
                                                            "_t",
                                                            comparatorId,
                                                            "_c",
                                                            targetId,
                                                            ".png"))
            title <- paste(comparatorName, "vs.", targetName, "- analysis ", analysisId)
            EmpiricalCalibration::plotCiCalibrationEffect(logRr = -data$logRr,
                                                          seLogRr = data$seLogRr,
                                                          trueLogRr = data$trueLogRr,
                                                          title = title,
                                                          xLabel = "Hazard ratio",
                                                          fileName = fileName)
        }
    }
}

# Calibration plots for interatcions -------------------------------------------------------------
indicationFolder <- file.path(outputFolder, indicationId)
diagnosticsFolder <- file.path(indicationFolder, "internalDiagnostics")
if (!file.exists(diagnosticsFolder)) {
    dir.create(diagnosticsFolder)
}
calibrationFolder <- file.path(diagnosticsFolder, "calibration")
if (!file.exists(calibrationFolder)) {
    dir.create(calibrationFolder)
}

indicationFolder <- file.path(outputFolder, indicationId)
exposureSummary <- read.csv(file.path(indicationFolder, "pairedExposureSummaryFilteredBySize.csv"))
analysesSum <- read.csv(file.path(indicationFolder, "analysisSummaryInteractions.csv"))
pathToCsv <- system.file("settings", "NegativeControls.csv", package = "Legend")
negativeControls <- read.csv(pathToCsv)
negativeControlIds <- negativeControls$cohortId
covariateData <- FeatureExtraction::loadCovariateData(file.path(indicationFolder, "allCovariates"))
subgroups <- ff::as.ram(covariateData$covariateRef[covariateData$covariateRef$analysisId == 998, ])
analysisId <- 3

sample <- 1:nrow(exposureSummary)
sample <- sample(nrow(exposureSummary), 100, replace = FALSE)
for (i in sample) {
    treatmentId <- exposureSummary$tprimeCohortDefinitionId[i]
    comparatorId <- exposureSummary$cprimeCohortDefinitionId[i]
    treatmentConceptId <- exposureSummary$tCohortDefinitionId[i]
    comparatorConceptId <- exposureSummary$cCohortDefinitionId[i]
    treatmentName <- exposureSummary$tName[i]
    comparatorName <- exposureSummary$cName[i]
    for (j in nrow(subgroups)) {
        subgroupCovariateId <- subgroups$covariateId[j]
        estimates <- analysesSum[analysesSum$analysisId == analysisId & analysesSum$targetId == treatmentId &
                                     analysesSum$comparatorId == comparatorId, ]

        negControls <- estimates[estimates$outcomeId %in% negativeControlIds, ]
        subgroupEstimates <- data.frame(logRr = negControls[,
                                                            paste0("logRrI", subgroupCovariateId)],
                                        seLogRr = negControls[,
                                                              paste0("seLogRrI", subgroupCovariateId)])
        fileName <- file.path(calibrationFolder, paste0("negControls_a",
                                                        analysisId,
                                                        "_t",
                                                        treatmentId,
                                                        "_c",
                                                        comparatorId,
                                                        "_s",
                                                        subgroupCovariateId,
                                                        ".png"))
        title <- paste(treatmentName, "vs.", comparatorName, "- ", subgroups$covariateName[j])
        EmpiricalCalibration::plotCalibrationEffect(logRrNegatives = subgroupEstimates$logRr,
                                                    seLogRrNegatives = subgroupEstimates$seLogRr,
                                                    title = title,
                                                    xLabel = "Hazard ratio ratio",
                                                    showCis = TRUE,
                                                    fileName = fileName)
    }
}

# Prior treatments distribution -----------------------------------------------------
indicationFolder <- file.path(outputFolder, indicationId)
diagnosticsFolder <- file.path(indicationFolder, "internalDiagnostics")
if (!file.exists(diagnosticsFolder)) {
    dir.create(diagnosticsFolder)
}
exposureSummary <- read.csv(file.path(indicationFolder, "pairedExposureSummaryFilteredBySize.csv"))
outcomeModelReference <- readRDS(file.path(indicationFolder,
                                           "cmOutput",
                                           "outcomeModelReference.rds"))
datas <- list()
for (i in 1:nrow(exposureSummary)) {
    targetId <- exposureSummary$tprimeCohortDefinitionId[i]
    comparatorId <- exposureSummary$cprimeCohortDefinitionId[i]
    cmDataFolder <- outcomeModelReference$cohortMethodDataFolder[outcomeModelReference$targetId == targetId &
                                                                     outcomeModelReference$comparatorId == comparatorId][1]
    cmData <- CohortMethod::loadCohortMethodData(cmDataFolder)
    ref <- ff::as.ram(cmData$covariateRef[cmData$covariateRef$analysisId == 999, ])
    covSubset <- ff::as.ram(cmData$covariates[ffbase::`%in%`(cmData$covariates$covariateId,
                                                             ff::as.ff(ref$covariateId)), ])
    covSubset <- merge(covSubset, cmData$cohorts[, c("rowId", "treatment")])
    counts <- aggregate(covariateValue ~ covariateId + treatment, covSubset, sum)
    counts <- merge(counts, ref[, c("covariateId", "covariateName")])
    counts <- rbind(counts[,
                           c("covariateName", "treatment", "covariateValue")],
                    data.frame(covariateName = "Prior treatments: 0",
                               treatment = c(1, 0),
                               covariateValue = c(sum(cmData$cohorts$treatment == 1) - sum(counts$covariateValue[counts$treatment ==
                                                                                                                     1]), sum(cmData$cohorts$treatment == 0) - sum(counts$covariateValue[counts$treatment == 0]))))
    counts$covariateName <- as.character(counts$covariateName)
    counts <- counts[order(counts$treatment, counts$covariateName), ]
    counts$targetName <- exposureSummary$tName[i]
    counts$comparatorName <- exposureSummary$cName[i]
    datas[[length(datas) + 1]] <- counts
}
data <- do.call("rbind", datas)
write.csv(data, file.path(diagnosticsFolder, "PriorExposureCounts.csv"), row.names = FALSE)


# Check subgroup covariates -----------------------------------------------------
indicationFolder <- file.path(outputFolder, indicationId)
diagnosticsFolder <- file.path(indicationFolder, "internalDiagnostics")
if (!file.exists(diagnosticsFolder)) {
    dir.create(diagnosticsFolder)
}
covariateData <- FeatureExtraction::loadCovariateData(file.path(indicationFolder, "allCovariates"))
covariateData$analysisRef

ref <- ff::as.ram(covariateData$covariateRef[covariateData$covariateRef$analysisId == 998, ])
covSubset <- ff::as.ram(covariateData$covariates[ffbase::`%in%`(covariateData$covariates$covariateId,
                                                                ff::as.ff(ref$covariateId)), ])
counts <- aggregate(covariateValue ~ covariateId, covSubset, sum)
counts <- merge(counts, ref[, c("covariateId", "covariateName")])
covariateData$metaData$populationSize

1  # Propensiy models --------------------------------------------------------------------------------------
indicationFolder <- file.path(outputFolder, indicationId)
diagnosticsFolder <- file.path(indicationFolder, "internalDiagnostics")
if (!file.exists(diagnosticsFolder)) {
    dir.create(diagnosticsFolder)
}
exposureSummary <- read.csv(file.path(indicationFolder, "pairedExposureSummaryFilteredBySize.csv"))
outcomeModelReference <- readRDS(file.path(indicationFolder,
                                           "cmOutput",
                                           "outcomeModelReference1.rds"))
cmFolder <- file.path(indicationFolder, "cmOutput")

# for (i in 1:nrow(exposureSummary)) {
getModel <- function(i, exposureSummary, outcomeModelReference) {
    # i <- which(exposureSummary$targetId == 11 & exposureSummary$comparatorId == 17)
    treatmentId <- exposureSummary$targetId[i]
    comparatorId <- exposureSummary$comparatorId[i]
    idx <- outcomeModelReference$targetId == treatmentId & outcomeModelReference$comparatorId == comparatorId &
        outcomeModelReference$analysisId == 1
    psFileName <- outcomeModelReference$sharedPsFile[idx][1]
    if (file.exists(file.path(cmFolder, psFileName))) {
        ps <- readRDS(file.path(cmFolder, psFileName))
        metaData <- attr(ps, "metaData")
        if (is.null(metaData$psError)) {
            cmDataFile <- outcomeModelReference$cohortMethodDataFolder[idx][1]
            cmData <- CohortMethod::loadCohortMethodData(file.path(cmFolder, cmDataFile))
            model <- CohortMethod::getPsModel(ps, cmData)
            ff::close.ffdf(cmData$covariates)
            ff::close.ffdf(cmData$covariateRef)
            ff::close.ffdf(cmData$analysisRef)
            # Truncate to first 25 covariates:
            if (nrow(model) > 25) {
                model <- model[1:25, ]
            }
        } else if (metaData$psError == "High correlation between covariate(s) and treatment detected. Perhaps you forgot to exclude part of the exposure definition from the covariates?") {
            model <- data.frame(coefficient = Inf,
                                covariateId = metaData$psHighCorrelation$covariateId,
                                covariateName = paste("High corr:",
                                                      metaData$psHighCorrelation$covariateName))
        } else {
            model <- data.frame(coefficient = NA,
                                covariateId = NA,
                                covariateName = paste("Error:", metaData$psError))
        }
        targetName <- exposureSummary$targetName[i]
        comparatorName <- exposureSummary$comparatorName[i]
        model$targetId <- treatmentId
        model$targetName <- targetName
        model$comparatorId <- comparatorId
        model$comparatorName <- comparatorName
        model$comparison <- paste(targetName, comparatorName, sep = " vs. ")
        return(model)
    }
    return(NULL)
}

data <- plyr::llply(1:nrow(exposureSummary),
                    getModel,
                    exposureSummary = exposureSummary,
                    outcomeModelReference = outcomeModelReference,
                    .progress = "text")
data <- do.call("rbind", data)
write.csv(data, file.path(diagnosticsFolder, "propensityModels.csv"), row.names = FALSE)


# Inspect interaction models -------------------------------------------
showNegativeControls <- TRUE
indicationFolder <- file.path(outputFolder, indicationId)
diagnosticsFolder <- file.path(indicationFolder, "internalDiagnostics")
if (!file.exists(diagnosticsFolder)) {
    dir.create(diagnosticsFolder)
}
exposureSummary <- read.csv(file.path(indicationFolder, "pairedExposureSummaryFilteredBySize.csv"))
outcomeModelReference <- readRDS(file.path(indicationFolder,
                                           "cmOutput",
                                           "outcomeModelReference2.rds"))
interactionModels <- outcomeModelReference[outcomeModelReference$analysisId == 3, ]

pathToCsv <- system.file("settings", "NegativeControls.csv", package = "Legend")
negativeControls <- read.csv(pathToCsv)
negativeControlIds <- negativeControls$cohortId
if (showNegativeControls) {
    interactionModels <- outcomeModelReference[outcomeModelReference$outcomeId %in% negativeControlIds, ]
} else {
    interactionModels <- outcomeModelReference[!(outcomeModelReference$outcomeId %in% negativeControlIds), ]
}
# model <- readRDS(file.path(indicationFolder, 'cmOutput', 'Analysis_3',
# 'om_t7035481505_c7976181505_o2829.rds')) summary(model) strataPop <-
# readRDS(file.path(indicationFolder, 'cmOutput', 'StratPop_l1_s1_p1_t587129_c1197129_s1_o2829.rds'))
# cmData <- CohortMethod::loadCohortMethodData(file.path(indicationFolder, 'cmOutput',
# 'CmData_l1_t587129_c1197129')) subgroupCovariateIds <- c(1998, 2998, 3998, 4998, 5998, 6998, 7998, 8998)
# debug(CohortMethod::fitOutcomeModel) CohortMethod::fitOutcomeModel(population = strataPop,
# cohortMethodData = cmData, stratified = TRUE, modelType = 'cox', interactionCovariateIds =
# subgroupCovariateIds)

files <- interactionModels$outcomeModelFile
sample <- sample(files, 10)
sample <- files
loadInteractionsFromModel <- function(fileName) {
    model <- readRDS(fileName)
    if (is.null(model$outcomeModelInteractionEstimates)) {
        return(NULL)
    } else {
        interactionEstimates <- model$outcomeModelInteractionEstimates
        interactionEstimates$fileName <- fileName
        return(interactionEstimates)
    }
}

d <- plyr::llply(sample, loadInteractionsFromModel, .progress = "text")
d <- do.call("rbind", d)

sum(is.na(d$seLogRr))
d <- d[!is.na(d$seLogRr), ]
library(ggplot2)
d$Group <- as.factor(d$interactionName)
d$Significant <- d$logLb95 > 0 | d$logUb95 < 0


temp1 <- aggregate(Significant ~ Group, data = d, length)
temp2 <- aggregate(Significant ~ Group, data = d, mean)

temp1$nLabel <- paste0(formatC(temp1$Significant, big.mark = ","), " estimates")
temp1$Significant <- NULL

temp2$meanLabel <- paste0(formatC(100 * (1 - temp2$Significant), digits = 1, format = "f"),
                          "% of CIs includes 1")
temp2$Significant <- NULL
dd <- merge(temp1, temp2)

breaks <- c(0.1, 0.25, 0.5, 1, 2, 4, 6, 8, 10)
theme <- element_text(colour = "#000000", size = 12)
themeRA <- element_text(colour = "#000000", size = 12, hjust = 1)
themeLA <- element_text(colour = "#000000", size = 12, hjust = 0)

alpha <- 1 - min(0.95 * (nrow(d)/nrow(dd)/50000)^0.1, 0.95)
plot <- ggplot(d, aes(x = logRr, y = seLogRr), environment = environment()) +
    geom_vline(xintercept = log(breaks), colour = "#AAAAAA", lty = 1, size = 0.5) +
    geom_abline(aes(intercept = 0, slope = 1/qnorm(0.025)),
                colour = rgb(0.8, 0, 0),
                linetype = "dashed",
                size = 1,
                alpha = 0.5,
                data = dd) +
    geom_abline(aes(intercept = 0, slope = 1/qnorm(0.975)),
                colour = rgb(0.8, 0, 0),
                linetype = "dashed",
                size = 1,
                alpha = 0.5,
                data = dd) +
    geom_point(size = 1, color = rgb(0, 0, 0, alpha = 0.05), alpha = alpha, shape = 16) +
    geom_hline(yintercept = 0) +
    geom_label(x = log(0.15),
               y = 0.95,
               alpha = 1,
               hjust = "left",
               aes(label = nLabel),
               size = 5,
               data = dd) +
    geom_label(x = log(0.15),
               y = 0.8,
               alpha = 1,
               hjust = "left",
               aes(label = meanLabel),
               size = 5,
               data = dd) +
    scale_x_continuous("Hazard ratio ratio",
                       limits = log(c(0.1, 10)),
                       breaks = log(breaks),
                       labels = breaks) +
    scale_y_continuous("Standard Error", limits = c(0, 1)) +
    facet_wrap(~Group) +
    theme(panel.grid.minor = element_blank(),
          panel.background = element_blank(),
          panel.grid.major = element_blank(),
          axis.ticks = element_blank(),
          axis.text.y = themeRA,
          axis.text.x = theme,
          axis.title = theme,
          legend.key = element_blank(),
          strip.text.x = theme,
          strip.text.y = theme,
          strip.background = element_blank(),
          legend.position = "none")
if (showNegativeControls) {
    ggsave(plot = plot,
           filename = file.path(diagnosticsFolder, "InteractionsNCs.png"),
           width = 12,
           height = 5,
           dpi = 300)
} else {
    ggsave(plot = plot, filename = file.path(diagnosticsFolder,
                                             "Interactions.png"), width = 12, height = 5, dpi = 300)
}
