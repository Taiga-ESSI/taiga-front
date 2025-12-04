###
# CREADOR POR: POL ALCOVERRO
# Descripción: Controlador y vista lógica del dashboard de métricas integradas con Learning Dashboard.
###

###
# This source code is licensed under the terms of the
# GNU Affero General Public License found in the LICENSE file in
# the root directory of this source tree.
#
# Copyright (c) 2021-present Kaleidos INC
# Pol Alcoverro added - Metrics module
#
# Metrics integration updated to mirror the Learning Dashboard extension
# including authentication flow and extended data retrieval.
###

taiga = @.taiga
mixOf = @.taiga.mixOf

module = angular.module("taigaMetrics")

#############################################################################
## Metrics Controller
## Pol Alcoverro added - Controller for displaying project metrics
#############################################################################

class MetricsController extends mixOf(taiga.Controller, taiga.PageMixin)
    @.$inject = [
        "$scope",
        "$rootScope",
        "$tgRepo",
        "$tgResources",
        "$routeParams",
        "$q",
        "$location",
        "$tgNavUrls",
        "tgAppMetaService",
        "$tgAuth",
        "$translate",
        "tgProjectService",
        "tgErrorHandlingService",
        "$tgHttp",
        "$tgUrls",
        "$timeout",
        "tgMetricsConfiguration",
        "tgMetricsCustomization"
    ]

    constructor: (@scope, @rootscope, @repo, @rs, @params, @q, @location, @navUrls, @appMetaService, @auth,
                  @translate, @projectService, @errorHandlingService, @http, @urls, @$timeout, metricsConfiguration,
                  metricsCustomization) ->
        @scope.sectionName = "METRICS.SECTION_NAME"
        @metricsConfig = metricsConfiguration
        @metricsHooks = metricsCustomization.getMetricsHooks()

        fallbackHooks =
            transformMetricsPayload: (ctx) -> ctx?.data
            transformMetricsView: (ctx) -> ctx?.viewData
            transformProjectMetrics: (ctx) -> ctx?.metrics
            transformHistoricalPayload: (ctx) -> ctx?.data
            transformTeamHistoricalCharts: (ctx) -> ctx?.charts
            transformProjectHistoricalCharts: (ctx) -> ctx?.charts
            resolveGaugeValue: (ctx) -> ctx?.defaultValue

        @metricsHooks = _.defaults(@metricsHooks or {}, fallbackHooks)

        providerResolver = @metricsConfig?.resolveProvider
        if angular.isFunction(providerResolver)
            @metricsProvider = providerResolver.call(@metricsConfig)
        else
            @metricsProvider = @metricsConfig?.provider or "external"

        if angular.isString(@metricsProvider)
            @metricsProvider = @metricsProvider.toLowerCase()
        else
            @metricsProvider = "external"

        @legacyLocalConfig = @.loadLocalConfig()
        @localConfig = null
        if @legacyLocalConfig?.provider
            @metricsProvider = @legacyLocalConfig.provider

        @scope.metricsAuth =
            authenticated: true
            username: null
            externalProjectId: null
            loading: false
            checking: false
            error: null
            form:
                username: ""

        @scope.metricsView =
            loading: false
            error: null
            isNewProject: false
            data: null
            errors: {}
            activeTab: "team"
            showHistorical: false
            showTesting: false
            historicalExpanded: {}  # Control de acordeón para secciones históricas
            teamSubTab: "overview"
            projectSubTab: "overview"
            teamOverview: @.buildTeamOverviewDefaultState()
            teamHistoricalFilters:
                metric: "all"
                user: "all"
                dateFrom: null
                dateTo: null
                preset: null
            teamHistoricalMetricOptions: [
                {id: "all", label: "METRICS.TEAM_HISTORICAL_METRIC_ALL"}
                {id: "tasks", label: "METRICS.TEAM_HISTORICAL_METRIC_TASKS"}
                {id: "closed_tasks", label: "METRICS.TEAM_HISTORICAL_METRIC_CLOSED_TASKS"}
                {id: "modified_lines", label: "METRICS.TEAM_HISTORICAL_METRIC_MODIFIED_LINES"}
                {id: "commits", label: "METRICS.TEAM_HISTORICAL_METRIC_COMMITS"}
            ]
            teamHistoricalUserOptions: [
                {id: "all", label: "METRICS.TEAM_HISTORICAL_ALL_USERS", translate: true}
            ]
            teamHistoricalCharts: []
            teamHistoricalSource: null
            projectHistoricalCharts: []
            projectHistoricalFilters:
                dateFrom: null
                dateTo: null
                preset: null
            # Date presets for quick filtering
            datePresetOptions: [
                {id: null, label: "METRICS.DATE_PRESET_CUSTOM", translate: true}
                {id: "last_7_days", label: "METRICS.DATE_PRESET_LAST_7_DAYS", translate: true}
                {id: "last_14_days", label: "METRICS.DATE_PRESET_LAST_14_DAYS", translate: true}
                {id: "last_30_days", label: "METRICS.DATE_PRESET_LAST_30_DAYS", translate: true}
                {id: "last_90_days", label: "METRICS.DATE_PRESET_LAST_90_DAYS", translate: true}
                {id: "current_month", label: "METRICS.DATE_PRESET_CURRENT_MONTH", translate: true}
                {id: "current_semester", label: "METRICS.DATE_PRESET_CURRENT_SEMESTER", translate: true}
                {id: "last_semester", label: "METRICS.DATE_PRESET_LAST_SEMESTER", translate: true}
                {id: "last_year", label: "METRICS.DATE_PRESET_LAST_YEAR", translate: true}
                {id: "all_time", label: "METRICS.DATE_PRESET_ALL_TIME", translate: true}
            ]

        @userColorPalette = @.buildUserColorPalette()
        @metricsCategoryPalettes = {}
        @qualityFactorNamesMap = {}
        @resetUserColorAssignments()

        @scope.availableTabs = [
            {id: "team", label: "METRICS.TABS.TEAM"}
            {id: "project", label: "METRICS.TABS.PROJECT"}
        ]

        @scope.setActiveTab = (tabId) =>
            @scope.metricsView.activeTab = tabId

        @scope.setTeamSubTab = (tabId) =>
            return unless tabId
            @scope.metricsView.teamSubTab = tabId
            if tabId is "historical"
                @.applyTeamHistoricalFilters()

        @scope.setProjectSubTab = (tabId) =>
            return unless tabId
            @scope.metricsView.projectSubTab = tabId
            if tabId is "historical"
                @.updateProjectHistoricalCharts(@scope.metricsView.data?.historicalMetrics)

        @scope.toggleHistorical = =>
            @scope.metricsView.showHistorical = !@scope.metricsView.showHistorical

        @scope.toggleHistoricalSection = (sectionName) =>
            if !@scope.metricsView.historicalExpanded[sectionName]?
                @scope.metricsView.historicalExpanded[sectionName] = true
            else
                @scope.metricsView.historicalExpanded[sectionName] = !@scope.metricsView.historicalExpanded[sectionName]

        @scope.loginMetrics = =>
            @.loginMetrics()

        @scope.logoutMetrics = =>
            @.logoutMetrics()

        @scope.reloadMetrics = =>
            @.loadMetrics(true)
        
        @scope.showTestingView = =>
            @scope.metricsView.showTesting = true
            setTimeout(@.drawTestingCharts, 100)
        
        @scope.hideTestingView = =>
            @scope.metricsView.showTesting = false

        @scope.clearTeamHistoricalDates = =>
            filters = @scope.metricsView.teamHistoricalFilters
            return unless filters?
            filters.dateFrom = null
            filters.dateTo = null
            filters.preset = null

        @scope.clearProjectHistoricalDates = =>
            filters = @scope.metricsView.projectHistoricalFilters
            return unless filters?
            filters.dateFrom = null
            filters.dateTo = null
            filters.preset = null

        # Apply date preset and calculate actual dates
        @scope.applyTeamDatePreset = (presetId) =>
            @.applyDatePreset(@scope.metricsView.teamHistoricalFilters, presetId)
        
        @scope.applyProjectDatePreset = (presetId) =>
            @.applyDatePreset(@scope.metricsView.projectHistoricalFilters, presetId)

        @scope.toggleTeamOverviewUser = (username) =>
            @.toggleTeamOverviewUser(username)

        @scope.resetTeamOverviewUsers = =>
            @.resetTeamOverviewUsers()

        @scope.$watch "metricsView.teamHistoricalFilters", (newFilters, oldFilters) =>
            return unless newFilters?
            return if newFilters is oldFilters
            @.applyTeamHistoricalFilters()
        , true

        @scope.$watch "metricsView.projectHistoricalFilters", (newFilters, oldFilters) =>
            return unless newFilters?
            return if newFilters is oldFilters
            @.applyProjectHistoricalFilters()
        , true

        @scope.$watch "metricsView.data.historicalMetrics", (historicalMetrics) =>
            return unless historicalMetrics?
            @.updateTeamHistoricalSource(historicalMetrics)
        
        promise = @.loadInitialData()

        promise.then =>
            title = @translate.instant("METRICS.PAGE_TITLE", {projectName: @scope.project.name})
            description = @translate.instant("METRICS.PAGE_DESCRIPTION", {
                projectName: @scope.project.name,
                projectDescription: @scope.project.description
            })
            @appMetaService.setAll(title, description)
            @.bootstrapMetricsAccess()

        promise.then null, @.onInitialDataError.bind(@)

    loadLocalConfig: ->
        try
            slug = @params.pslug
            saved = localStorage.getItem("taigaMetricsConfig_#{slug}")
            return JSON.parse(saved) if saved
        catch e
            console.error "Error loading local config", e
        return null

    fetchProjectConfig: ->
        slug = @params.pslug
        return @q.when(@legacyLocalConfig) unless slug

        url = @urls.resolve("metrics-config")
        params = {project: slug}

        return @http.get(url, params, {withCredentials: true})
            .then (response) =>
                config = @.normalizeConfigPayload(response?.data)
                if config
                    console.log "Metrics: Loaded configuration from SERVER for project #{slug}", config
                    @localConfig = config
                    if config.provider
                        @metricsProvider = config.provider
                    if config.externalProjectId
                        @scope.metricsAuth.externalProjectId = config.externalProjectId
                else
                    console.log "Metrics: No configuration from server, using defaults/legacy"
                    @localConfig = null
                return @localConfig
            .catch (error) =>
                console.error "Metrics: unable to load persisted config", error
                if @legacyLocalConfig
                    console.log "Metrics: Using LEGACY local config", @legacyLocalConfig
                    @localConfig = @legacyLocalConfig
                    if @localConfig.provider
                        @metricsProvider = @localConfig.provider
                    if @localConfig.externalProjectId and !@scope.metricsAuth.externalProjectId
                        @scope.metricsAuth.externalProjectId = @localConfig.externalProjectId
                else
                    console.log "Metrics: Using DEFAULT hardcoded config"
                return @localConfig

    normalizeConfigPayload: (data) ->
        return null unless data and angular.isObject(data)

        normalized =
            provider: null
            classification: data.classification or {}
            externalProjectId: data.external_project_id or data.externalProjectId or null
            projectMetricsOrder: data.project_metrics_order or data.projectMetricsOrder or []
            teamMetricsOrder: data.team_metrics_order or data.teamMetricsOrder or []

        providerValue = data.provider or data.metrics_provider
        if angular.isString(providerValue)
            normalized.provider = providerValue.toLowerCase()

        defaultProjectOrder = if angular.isArray(@metricsConfig?.projectMetricsOrder) then @metricsConfig.projectMetricsOrder.slice() else []
        defaultTeamOrder = if angular.isArray(@metricsConfig?.teamMetricsOrder) then @metricsConfig.teamMetricsOrder.slice() else []

        if angular.isString(normalized.externalProjectId)
            normalized.externalProjectId = normalized.externalProjectId.trim()
        else
            normalized.externalProjectId = null

        if !angular.isObject(normalized.classification)
            normalized.classification = {}

        if !angular.isArray(normalized.projectMetricsOrder)
            normalized.projectMetricsOrder = []
        if normalized.projectMetricsOrder.length is 0 and defaultProjectOrder.length > 0
            normalized.projectMetricsOrder = defaultProjectOrder

        if !angular.isArray(normalized.teamMetricsOrder)
            normalized.teamMetricsOrder = []
        if normalized.teamMetricsOrder.length is 0 and defaultTeamOrder.length > 0
            normalized.teamMetricsOrder = defaultTeamOrder

        return normalized

    resolveLocalClassification: (metricId) ->
        return null unless metricId?
        return null unless @localConfig?.classification
        classification = @localConfig.classification[metricId]
        if classification?
            return classification
        lower = metricId.toString().toLowerCase()
        return @localConfig.classification[lower] if lower isnt metricId and @localConfig.classification[lower]?
        return null

    resolveMetricClassificationValue: (metric) ->
        return null unless metric?
        classification = null
        if metric.id?
            classification = @.resolveLocalClassification(metric.id)
        if !classification and metric.externalId?
            classification = @.resolveLocalClassification(metric.externalId)
        return classification

    matchesConfiguredMetric: (configuredValue, metricId, metricExternalId, allowPrefix = true) ->
        return false unless configuredValue?
        normalizedConfig = configuredValue.toString().toLowerCase()
        normalizedMetricId = if metricId? then metricId.toString().toLowerCase() else null
        normalizedExternalId = if metricExternalId? then metricExternalId.toString().toLowerCase() else null

        matchesExact = (value) ->
            value? and value == normalizedConfig

        matchesPrefix = (value) ->
            return false unless allowPrefix and value?
            value.indexOf("#{normalizedConfig}_") is 0

        return true if matchesExact(normalizedMetricId) or matchesExact(normalizedExternalId)
        return true if matchesPrefix(normalizedMetricId) or matchesPrefix(normalizedExternalId)
        return false

    loadProject: ->
        project = @projectService.project.toJS()

        @scope.projectId = project.id
        @scope.project = project
        @scope.projectSlug = project.slug
        @scope.$emit('project:loaded', project)

        defaultExternal = @metricsConfig.resolveExternalProjectId(project.slug)
        if !@scope.metricsAuth.externalProjectId
            @scope.metricsAuth.externalProjectId = defaultExternal

        return project

    bootstrapMetricsAccess: ->
        # No auth flow required: use project config to resolve IDs/provider
        @scope.metricsAuth.authenticated = true
        @scope.metricsAuth.checking = false
        @scope.metricsAuth.username = @scope.projectSlug or @scope.project?.slug
        @scope.metricsAuth.externalProjectId ?= @metricsConfig.resolveExternalProjectId(@scope.projectSlug)
        @.loadMetrics(true)

    loginMetrics: ->
        return if @scope.metricsAuth.loading

        username = @scope.metricsAuth.form.username

        if !username
            @scope.metricsAuth.error = "METRICS.LOGIN_USERNAME_REQUIRED"
            return

        externalId = username or @scope.metricsAuth.externalProjectId or @metricsConfig.resolveExternalProjectId(@scope.projectSlug)
        payload = {
            username: username
            project: externalId
            source: @metricsProvider
        }

        @scope.metricsAuth.loading = true
        @scope.metricsAuth.error = null

        url = @urls.resolve("metrics-login")
        @http.post(url, payload, null, {withCredentials: true})
            .then (response) =>
                data = response?.data || {}
                @scope.metricsAuth.authenticated = true
                @scope.metricsAuth.username = data.username or username
                @scope.metricsAuth.externalProjectId = externalId
                @scope.metricsAuth.form.username = @scope.metricsAuth.username
                @scope.metricsAuth.loading = false
                @.loadMetrics(true)
            .catch (error) =>
                console.error "✗ Login failed:", error
                @scope.metricsAuth.loading = false
                errorKey = error?.data?.error
                @scope.metricsAuth.error = @.resolveErrorKey(errorKey, "METRICS.LOGIN_ERROR_GENERIC")

    logoutMetrics: ->
        return if @scope.metricsAuth.loading

        @scope.metricsAuth.loading = true
        @scope.metricsAuth.error = null

        url = @urls.resolve("metrics-logout")
        payload =
            source: @metricsProvider
        @http.post(url, payload, null, {withCredentials: true})
            .then =>
                @scope.metricsAuth.loading = false
                @scope.metricsAuth.authenticated = false
                @scope.metricsAuth.username = null
                @scope.metricsAuth.externalProjectId = @metricsConfig.resolveExternalProjectId(@scope.projectSlug)
                @scope.metricsView.data = null
            .catch (error) =>
                console.error "Error logging out from metrics:", error
                @scope.metricsAuth.loading = false
                @scope.metricsAuth.error = @.resolveErrorKey(error?.data?.error, "METRICS.LOGOUT_ERROR")

    loadMetrics: (force = false) ->
        return if @scope.metricsView.loading and !force

        projectSlug = @scope.projectSlug

        if !projectSlug
            @scope.metricsView.error = "METRICS.LOAD_ERROR"
            @scope.metricsView.data = null
            return

        externalId = @scope.metricsAuth.externalProjectId or @metricsConfig.resolveExternalProjectId(projectSlug)

        params =
            project: projectSlug
            source: @metricsProvider

        if externalId
            params.external = externalId

        @scope.metricsView.loading = true
        @scope.metricsView.error = null
        @scope.metricsView.isNewProject = false
        @scope.metricsView.errors = {}
        @.resetTeamOverviewState()

        url = @urls.resolve("metrics")
        @http.get(url, params, {withCredentials: true})
            .then (response) =>
                data = response?.data || {}

                payloadContext =
                    data: angular.copy(data)
                    project: @scope.project
                    scope: @scope

                transformedPayload = @metricsHooks.transformMetricsPayload(payloadContext)
                if transformedPayload isnt undefined
                    data = transformedPayload
                else if payloadContext?.data isnt undefined
                    data = payloadContext.data

                @resetUserColorAssignments()

                @scope.metricsAuth.externalProjectId = data.external_project_id or externalId

                metricsCategoriesData = data.metrics_categories or data.metricsCategories or {}
                @metricsCategoryPalettes = @.buildMetricCategoryPalettes(metricsCategoriesData)

                # Build quality factor id->name map for display purposes
                # The main metrics array contains quality factors with their names
                # Each quality factor has id (e.g., "modifiedlinescontribution") and name (e.g., "Modified Lines Contribution")
                allMetricsData = data.metrics or []
                @qualityFactorNamesMap = @.buildQualityFactorNamesMap(allMetricsData)

                processedMetrics = @.processGessiMetrics(data.metrics or [])
                displayMetricGroups = @.buildMetricDisplayGroups(data.metrics or [])
                projectMetricsList = @.prepareProjectMetrics(data.metrics or [])
                studentsRaw = data.students
                
                # Pol Alcoverro added: Associate metrics with students using their identities
                allMetrics = data.metrics or []
                if studentsRaw and angular.isArray(studentsRaw)
                    for student in studentsRaw when student
                        # Get the student's TAIGA and GITHUB usernames
                        taigaUsername = student.identities?.TAIGA?.username
                        githubUsername = student.identities?.GITHUB?.username
                        
                        # Filter metrics that belong to this student
                        studentMetrics = []
                        for metric in allMetrics when metric?.id
                            metricId = metric.id.toLowerCase()
                            
                            # Check if this metric belongs to the student
                            matchesTaiga = taigaUsername and metricId.includes("_#{taigaUsername.toLowerCase()}")
                            matchesGithub = githubUsername and metricId.includes("_#{githubUsername.toLowerCase()}")
                            
                            if matchesTaiga or matchesGithub
                                studentMetrics.push(metric)
                        
                        # Assign the filtered metrics to the student
                        student.metrics = studentMetrics
                # End Pol Alcoverro added
                
                normalizedStudents = @.normalizeStudentsCollection(studentsRaw)
                
                processedUsers = @.processStudentsMetrics(normalizedStudents)
                
                processedUsersList = @.usersMetricsToArray(processedUsers)

                @.registerUserColors(processedUsersList)
                
                hoursData = data.hours or {}
                hasHoursData = hoursData? and typeof hoursData is "object" and Object.keys(hoursData).length > 0
                hoursChart = if hasHoursData then @.prepareHoursPieData(hoursData) else null
                # Prepare strategic indicators for display
                processedStrategicIndicators = @.prepareStrategicIndicators(data.strategic_indicators or [])
                
                # Prepare quality factors for display
                processedQualityFactors = @.prepareQualityFactors(data.quality_factors or [])
                
                if Object.keys(processedUsers).length is 0
                    processedUsers = @.extractUsersFromMetrics(data.metrics or [])
                    processedUsersList = @.usersMetricsToArray(processedUsers)

                @.initializeTeamHistoricalUsers(processedUsersList)

                # Create visualizations for team view
                studentsOverallRadar = @.buildStudentsOverallRadar(processedUsersList)
                studentsClosedTasksBar = @.buildClosedTasksComparison(processedUsersList)

                viewData = {
                    metrics: processedMetrics,
                    usersMetrics: processedUsers,
                    usersMetricsList: processedUsersList,
                    rawMetrics: data.metrics or [],
                    projectMetrics: projectMetricsList,
                    rawStudents: studentsRaw,
                    strategicIndicators: processedStrategicIndicators,
                    qualityFactors: processedQualityFactors,
                    projectMetricGroups: displayMetricGroups.project,
                    teamMetricGroups: displayMetricGroups.team,
                    hours: hoursData,
                    hoursChart: hoursChart,
                    studentsOverallRadar: studentsOverallRadar,
                    studentsClosedTasksBar: studentsClosedTasksBar,
                    metricsCategories: metricsCategoriesData,
                    historicalMetrics: {
                        userMetrics: {}
                        projectMetrics: {}
                        strategicMetrics: {}
                        qualityFactors: {}
                    },
                    lastReport: {}
                }

                viewContext =
                    viewData: viewData
                    rawPayload: data
                    project: @scope.project
                    scope: @scope

                transformedView = @metricsHooks.transformMetricsView(viewContext)

                if transformedView isnt undefined
                    @scope.metricsView.data = transformedView
                else if viewContext?.viewData isnt undefined
                    @scope.metricsView.data = viewContext.viewData
                else
                    @scope.metricsView.data = viewData

                @.initializeTeamOverviewState()

                @scope.metricsView.teamHistoricalSource = null
                @scope.metricsView.teamHistoricalCharts = []
                @scope.metricsView.projectHistoricalCharts = []

                @scope.metricsView.errors = data.errors or {}
                @scope.metricsView.isNewProject = data.is_new_project
                @scope.metricsView.loading = false
                
                # Load historical metrics after current metrics are loaded
                @.loadHistoricalMetrics()
                
                # Don't trigger digest, let Angular handle it naturally
            .catch (error) =>
                console.error "Error loading metrics:", error
                @scope.metricsView.loading = false
                @scope.metricsView.error = @.resolveErrorKey(error?.data?.error, "METRICS.LOAD_ERROR")
                @scope.metricsView.data = null
                @.resetTeamOverviewState()
                @scope.metricsView.teamHistoricalSource = null
                @scope.metricsView.teamHistoricalCharts = []
                @scope.metricsView.projectHistoricalCharts = []

    loadHistoricalMetrics: ->
        # Don't load historical metrics if not authenticated
        return unless @scope.metricsAuth.authenticated
        return unless @scope.projectSlug

        projectSlug = @scope.projectSlug
        externalId = @scope.metricsAuth.externalProjectId or @metricsConfig.resolveExternalProjectId(projectSlug)

        params =
            project: projectSlug
            source: @metricsProvider

        if externalId
            params.external = externalId

        url = @urls.resolve("metrics-historical")
        
        @http.get(url, params, {withCredentials: true})
            .then (response) =>
                data = response?.data || {}
                historicalData = data.historical_data || {}
                
                # Process historical data into user and project charts
                processedHistorical = @.processHistoricalData(historicalData)

                historicalContext =
                    data: processedHistorical
                    raw: historicalData
                    project: @scope.project
                    scope: @scope

                transformedHistorical = @metricsHooks.transformHistoricalPayload(historicalContext)
                if transformedHistorical isnt undefined
                    processedHistorical = transformedHistorical
                else if historicalContext?.data isnt undefined
                    processedHistorical = historicalContext.data

                
                # Update the view data with historical metrics
                if @scope.metricsView.data
                    @scope.metricsView.data.historicalMetrics = processedHistorical
                    # Force Angular to update the view - use $timeout to trigger digest cycle
                    @$timeout (->), 0
                    @.updateTeamHistoricalSource(processedHistorical)
                else
                    @scope.metricsView.data = {historicalMetrics: processedHistorical}
                    @$timeout (->), 0
                    @.updateTeamHistoricalSource(processedHistorical)
                
            .catch (error) =>
                console.error "Error loading historical metrics:", error
                if @scope.metricsView.data
                    @scope.metricsView.data.historicalMetrics = {
                        error: @.resolveErrorKey(error?.data?.error, "METRICS.HISTORICAL_LOAD_ERROR")
                    }
                @scope.metricsView.teamHistoricalSource = null
                @scope.metricsView.teamHistoricalCharts = []
                @scope.metricsView.projectHistoricalCharts = []

    normalizeStudentsCollection: (students) ->
        return [] unless students?

        if angular.isArray(students)
            return students

        if typeof students is "object"
            normalized = []

            # Handle payloads nested under a 'results' property
            if angular.isArray(students.results)
                return students.results

            for own username, metricsList of students
                normalized.push({
                    username: username
                    name: username
                    metrics: metricsList
                })
            return normalized

        return []

    normalizeCategoryKey: (name) ->
        return null unless name?
        key = name.toString().trim().toLowerCase()
        return if key.length then key else null

    buildMetricCategoryPalettes: (categoriesData) ->
        grouped = {}
        return grouped unless categoriesData?

        entries = []

        if angular.isArray(categoriesData)
            entries = categoriesData
        else if typeof categoriesData is "object"
            for own _, value of categoriesData when value?
                if angular.isArray(value)
                    entries = entries.concat(value)
                else
                    entries.push(value)

        for entry in entries when entry?
            nameKey = @.normalizeCategoryKey(entry.name or entry.category or entry.displayName)
            continue unless nameKey

            grouped[nameKey] ?= []
            upper = parseFloat(entry.upperThreshold)

            grouped[nameKey].push({
                color: entry.color or entry.hex or "#2563EB"
                upperThreshold: if isFinite(upper) then Math.max(0, upper) else null
                type: entry.type or null
                raw: entry
            })

        for nameKey, palette of grouped
            valid = palette.filter (item) -> item.upperThreshold? and isFinite(item.upperThreshold)
            if valid.length > 0
                valid.sort (a, b) ->
                    if a.upperThreshold < b.upperThreshold then -1
                    else if a.upperThreshold > b.upperThreshold then 1
                    else 0
                grouped[nameKey] = valid
            else
                grouped[nameKey] = palette.slice()

        grouped

    normalizeMetricValue: (rawValue) ->
        return 0 unless rawValue?

        value = rawValue

        if Array.isArray(value)
            # Look for the first usable entry in arrays like [{value: 0.7}]
            for item in value when item?
                if typeof item is "number"
                    value = item
                    break
                if typeof item is "string" and item.trim()? and !isNaN(parseFloat(item))
                    value = parseFloat(item)
                    break
                if typeof item is "object"
                    candidates = [item.value, item.first, item.percentage, item.percent, item.score]
                    for candidate in candidates when candidate?
                        if typeof candidate in ["number", "string"]
                            value = candidate
                            break
                    break if typeof value isnt "object"

        if typeof value is "object"
            candidates = [
                value.value
                value.first
                value.percentage
                value.percent
                value.score
                value.amount
                value.total
                value.current
            ]

            chosen = null
            for candidate in candidates when candidate?
                if typeof candidate in ["number", "string"]
                    chosen = candidate
                    break

            if chosen?
                value = chosen
            else
                for own _, candidateValue of value
                    if typeof candidateValue is "number"
                        value = candidateValue
                        break
                    if typeof candidateValue is "string" and candidateValue.trim()? and !isNaN(parseFloat(candidateValue))
                        value = parseFloat(candidateValue)
                        break

        if typeof value is "string"
            parsed = parseFloat(value)
            value = if isNaN(parsed) then 0 else parsed

        value = Number(value) or 0

        # Values coming from gessi-dashboard are typically ratios (0-1)
        if Math.abs(value) <= 1
            value = value * 100

        # Avoid negative percentages and clamp very large spikes
        value = Math.max(0, value)

        # Keep two decimal precision for display purposes
        return Math.round(value * 100) / 100

    buildMetricDetail: (metric) ->
        return null unless metric?

        normalizedValue = @.normalizeMetricValue(metric.value)

        return {
            id: metric.id
            name: metric.name or metric.id
            value: normalizedValue
            rawValue: metric.value
            valueDescription: metric.value_description or metric.valueDescription
            date: metric.date or metric.timestamp or metric.updated_at or metric.lastUpdated
            description: metric.description
            qualityFactors: metric.qualityFactors or metric.quality_factors or []
        }

    processUsersMetrics: (rawData) ->
        processed = {}

        for username, metrics of rawData
            totalTasks = metrics.totalTasks ? metrics.total_tasks ? 0
            completedTasks = metrics.completedTasks ? metrics.completed_tasks ? 0
            totalUS = metrics.totalUS ? metrics.total_us ? 0
            completedUS = metrics.completedUS ? metrics.completed_us ? 0

            tasksPercentage = if totalTasks > 0 then Math.round((completedTasks / totalTasks) * 100) else 0
            usPercentage = if totalUS > 0 then Math.round((completedUS / totalUS) * 100) else 0

            processed[username] = {
                totalTasks: totalTasks
                completedTasks: completedTasks
                totalUS: totalUS
                completedUS: completedUS
                tasksPercentage: tasksPercentage
                usPercentage: usPercentage
            }

        @.decorateUsersMetrics(processed)

        return processed

    decorateUsersMetrics: (users) ->
        return users unless users

        for username, data of users
            continue unless username and data
            data.radarData = @.buildUserRadarData(username, data)
        return users

    buildUserRadarData: (username, userData) ->
        return null unless username and userData

        assignedTasks = Number(userData.assignedTasks) or 0
        closedTasks = Number(userData.closedTasks) or 0
        commits = Number(userData.commits) or 0
        modifiedLines = Number(userData.modifiedLines) or 0

        if isNaN(assignedTasks) then assignedTasks = 0
        if isNaN(closedTasks) then closedTasks = 0
        if isNaN(commits) then commits = 0
        if isNaN(modifiedLines) then modifiedLines = 0

        @.registerUserColors([username])
        colorPalette = @.resolveUserColor(username)
        backgroundColor = colorPalette?.fill or 'rgba(59, 130, 246, 0.26)'
        borderColor = colorPalette?.border or '#3B82F6'

        radarData = {
            labels: [
                'Tasks'
                'Closed Tasks'
                'Commits'
                'Modified Lines'
            ]
            datasets: [{
                label: username
                data: [
                    assignedTasks
                    closedTasks
                    commits
                    modifiedLines
                ]
                backgroundColor: backgroundColor
                borderColor: borderColor
                borderWidth: 2
                pointBackgroundColor: borderColor
                pointBorderColor: '#ffffff'
                pointHoverBackgroundColor: '#ffffff'
                pointHoverBorderColor: borderColor
            }]
        }

        return radarData

    processStudentsMetrics: (studentsRaw) ->
        processed = {}

        students = @.normalizeStudentsCollection(studentsRaw)
        return processed unless students?.length

        for student in students when student
            username = student?.username or student?.name or student?.displayName or student?.id
            unless username? and username.toString().trim().length
                username = student?.identities?.TAIGA?.username or student?.identities?.GITHUB?.username
            continue unless username? and username.toString().trim().length

            normalizedName = username.toString().trim()
            metricsList = student.metrics or student.metrics_list or student.metricsList or []

            if !angular.isArray(metricsList) and metricsList? and typeof metricsList is "object"
                metricsObject = metricsList
                metricsList = (Object.keys(metricsObject or {}).map (key) -> metricsObject[key])

            metricsList = (metricsList or []).filter (metric) -> metric?

            entry = {
                username: normalizedName
                displayName: student?.displayName or student?.name or normalizedName
                assignedTasks: 0
                closedTasks: 0
                commits: 0
                modifiedLines: 0
                totalTasks: 0
                completedTasks: 0
                totalUS: 0
                completedUS: 0
                tasksPercentage: 0
                usPercentage: 0
                metricsDetails: []
                rawMetrics: if angular.isArray(metricsList) then metricsList.slice() else []
            }

            seenMetricIds = {}

            for metric in metricsList when metric?.id?
                metricKey = metric.id.toString()
                next if seenMetricIds[metricKey]

                detail = @.buildMetricDetail(metric)
                if detail?
                    entry.metricsDetails.push(detail)
                seenMetricIds[metricKey] = true

                metricId = metricKey.toLowerCase()
                metricValue = detail?.value
                metricValue ?= @.normalizeMetricValue(metric.value)

                metricId = metricKey.toLowerCase()
                metricValue = detail?.value
                metricValue ?= @.normalizeMetricValue(metric.value)

                configuredKeys = @metricsConfig.teamMetricsOrder or []
                if !angular.isArray(configuredKeys) or configuredKeys.length is 0
                    configuredKeys = [
                        "assignedtasks"
                        "closedtasks"
                        "completedtasks"
                        "commits"
                        "modifiedlines"
                        "linesmodified"
                        "totalus"
                        "completedus"
                        "closedus"
                    ]

                for rawKey in configuredKeys when rawKey?
                    configuredKey = rawKey.toString().toLowerCase()
                    continue unless metricId.indexOf(configuredKey) isnt -1

                    if configuredKey is "assignedtasks"
                        entry.assignedTasks = metricValue
                        entry.totalTasks = Math.max(entry.totalTasks, metricValue)
                    else if configuredKey is "closedtasks" or configuredKey is "completedtasks"
                        entry.closedTasks = metricValue
                        entry.completedTasks = metricValue
                        entry.tasksPercentage = metricValue
                    else if configuredKey is "commits"
                        entry.commits = metricValue
                    else if configuredKey is "modifiedlines" or configuredKey is "linesmodified"
                        entry.modifiedLines = metricValue
                    else if configuredKey is "totalus"
                        entry.totalUS = metricValue
                    else if configuredKey is "completedus" or configuredKey is "closedus"
                        entry.completedUS = metricValue
                        entry.usPercentage = metricValue

            # Calcular porcentajes
            if entry.totalTasks > 0 and entry.completedTasks > 0
                ratio = entry.completedTasks
                if entry.completedTasks > entry.totalTasks and entry.totalTasks > 0
                    ratio = (entry.completedTasks / entry.totalTasks) * 100
                entry.tasksPercentage = Math.min(100, Math.round(ratio * 100) / 100) if ratio?

            if entry.totalUS > 0 and entry.completedUS > 0
                ratioUS = entry.completedUS
                if entry.completedUS > entry.totalUS and entry.totalUS > 0
                    ratioUS = (entry.completedUS / entry.totalUS) * 100
                entry.usPercentage = Math.min(100, Math.round(ratioUS * 100) / 100) if ratioUS?

            entry.metricsDetails.sort (a, b) ->
                aName = (a?.name or "").toString().toLowerCase()
                bName = (b?.name or "").toString().toLowerCase()
                if aName < bName then -1 else if aName > bName then 1 else 0

            processed[normalizedName] = entry

        @.decorateUsersMetrics(processed)

        return processed

    usersMetricsToArray: (usersObject) ->
        return [] unless usersObject

        list = []
        for username, data of usersObject
            continue unless username and data

            data.radarData ?= @.buildUserRadarData(username, data)

            cloned = angular.extend({}, data)
            cloned.username = username
            cloned.displayName = data.displayName or username
            cloned.radarData = data.radarData

            if angular.isArray(data.metricsDetails)
                cloned.metricsDetails = data.metricsDetails.slice()
            else
                cloned.metricsDetails = []

            if cloned.metricsDetails.length is 0 and angular.isArray(data.rawMetrics)
                details = []
                seen = {}
                for metric in data.rawMetrics when metric?.id?
                    detail = @.buildMetricDetail(metric)
                    continue unless detail?
                    continue if seen[detail.id]
                    seen[detail.id] = true
                    details.push(detail)
                cloned.metricsDetails = details if details.length > 0

            list.push(cloned)

        list.sort (a, b) ->
            aName = (a.username or "").toString().toLowerCase()
            bName = (b.username or "").toString().toLowerCase()
            if aName < bName then -1 else if aName > bName then 1 else 0

        return list

    processGessiMetrics: (metricsArray) ->
        # Process gessi-dashboard metrics array into organized structure
        processed = {
            byCategory: {}
            byUser: {}
            all: metricsArray
        }

        for metric in metricsArray
            # Group by quality factor (category)
            if metric.qualityFactors and metric.qualityFactors.length > 0
                for factor in metric.qualityFactors
                    processed.byCategory[factor] ?= []
                    processed.byCategory[factor].push(metric)

            # Extract user-specific metrics
            if metric.id and metric.id.includes("_")
                parts = metric.id.split("_")
                if parts.length >= 2
                    metricType = parts[0]
                    userName = parts[1..].join("_")
                    
                    processed.byUser[userName] ?= []
                    processed.byUser[userName].push(metric)

        return processed

    extractUsersFromMetrics: (metricsArray) ->
        # Extract user metrics from gessi-dashboard format
        users = {}
        
        for metric in metricsArray when metric?.id?
            # Look for user-specific metrics
            if metric.id and (metric.id.includes("assignedtasks_") or 
                             metric.id.includes("closedtasks_") or
                             metric.id.includes("commits_") or
                             metric.id.includes("modifiedlines_") or
                             metric.id.includes("completedus_") or
                             metric.id.includes("totalus_"))
                
                parts = metric.id.split("_")
                if parts.length >= 2
                    metricType = parts[0]
                    userName = parts[1..].join("_")
                    
                    users[userName] ?= {
                        username: userName
                        assignedTasks: 0
                        closedTasks: 0
                        commits: 0
                        modifiedLines: 0
                        totalTasks: 0
                        completedTasks: 0
                        totalUS: 0
                        completedUS: 0
                        tasksPercentage: 0
                        usPercentage: 0
                        metricsDetails: []
                        rawMetrics: []
                    }

                    detail = @.buildMetricDetail(metric)
                    normalizedValue = detail?.value
                    normalizedValue ?= @.normalizeMetricValue(metric.value)

                    # Store the raw metric object for display
                    if detail?
                        existingIds = users[userName]._metricsIds ?= {}
                        unless existingIds[detail.id]
                            users[userName].metricsDetails.push(detail)
                            existingIds[detail.id] = true
                    users[userName].rawMetrics ?= []
                    users[userName].rawMetrics.push(metric)
                    
                    # Map metric types to user properties
                    # Values are percentages (0-1), we multiply by 100 for display
                    if metricType == "assignedtasks"
                        users[userName].assignedTasks = normalizedValue
                        users[userName].totalTasks = Math.max(users[userName].totalTasks, normalizedValue)
                    else if metricType == "closedtasks" or metricType == "completedtasks"
                        users[userName].closedTasks = normalizedValue
                        users[userName].completedTasks = normalizedValue
                        users[userName].tasksPercentage = normalizedValue
                    else if metricType == "commits"
                        users[userName].commits = normalizedValue
                    else if metricType == "modifiedlines"
                        users[userName].modifiedLines = normalizedValue
                    else if metricType == "totalus"
                        users[userName].totalUS = normalizedValue
                    else if metricType == "completedus" or metricType == "closedus"
                        users[userName].completedUS = normalizedValue
                        users[userName].usPercentage = normalizedValue

                    if users[userName].totalTasks > 0 and users[userName].completedTasks > 0
                        ratio = users[userName].completedTasks
                        if users[userName].completedTasks > users[userName].totalTasks and users[userName].totalTasks > 0
                            ratio = (users[userName].completedTasks / users[userName].totalTasks) * 100
                        users[userName].tasksPercentage = Math.min(100, Math.round(ratio * 100) / 100)
                    if users[userName].totalUS > 0 and users[userName].completedUS > 0
                        ratioUS = users[userName].completedUS
                        if users[userName].completedUS > users[userName].totalUS and users[userName].totalUS > 0
                            ratioUS = (users[userName].completedUS / users[userName].totalUS) * 100
                        users[userName].usPercentage = Math.min(100, Math.round(ratioUS * 100) / 100)

        # Cleanup helper metadata
        for userName, userData of users when userData?._metricsIds?
            delete userData._metricsIds
        
        for userName, userData of users when angular.isArray(userData?.metricsDetails)
            userData.metricsDetails.sort (a, b) ->
                aName = (a?.name or "").toString().toLowerCase()
                bName = (b?.name or "").toString().toLowerCase()
                if aName < bName then -1 else if aName > bName then 1 else 0

        @.decorateUsersMetrics(users)

        return users
    
    # Format user metrics for radar chart visualization
    prepareUserRadarData: (username, userData) ->
        return null unless userData
        userData.radarData ?= @.buildUserRadarData(username, userData)
        return userData.radarData
    
    # Prepare radar chart with multiple users
    prepareMultiUserRadarData: (usersData) ->
        return null unless usersData
        
        datasets = []
        usernames = []
        datasetMap = usersData

        if angular.isArray(usersData)
            datasetMap = {}
            for dataEntry, idx in usersData when dataEntry?
                username = dataEntry.username or dataEntry.displayName or dataEntry.name or "User #{idx + 1}"
                datasetMap[username] = dataEntry
        else if typeof usersData isnt "object"
            return null

        usernames = Object.keys(datasetMap)
        usernames.sort (a, b) -> a.toString().localeCompare(b.toString())

        @.registerUserColors(usernames)

        for username in usernames
            userData = datasetMap[username]
            colorPalette = @.resolveUserColor(username)
            borderColor = colorPalette?.border or '#3B82F6'
            fillColor = colorPalette?.fill or 'rgba(59, 130, 246, 0.26)'
            datasets.push({
                label: username
                data: [
                    userData?.assignedTasks || 0
                    userData?.closedTasks || 0
                    userData?.commits || 0
                    userData?.modifiedLines || 0
                ]
                backgroundColor: fillColor
                borderColor: borderColor
                borderWidth: 2
                pointBackgroundColor: borderColor
                pointBorderColor: '#ffffff'
                pointHoverBackgroundColor: '#ffffff'
                pointHoverBorderColor: borderColor
            })
        
        return {
            labels: [
                'Tasks'
                'Closed Tasks'
                'Commits'
                'Modified Lines'
            ]
            datasets: datasets
        }

    prepareProjectMetrics: (metricsArray) ->
        return [] unless angular.isArray(metricsArray)

        metricsById = {}
        for metric in metricsArray
            continue unless metric
            # Skip user-scoped metrics (they belong in Team view)
            isUserMetric = @.isUserMetricId(metric.id) or @.isUserMetricId(metric.externalId)
            continue if isUserMetric

            if metric.externalId
                metricsById[metric.externalId.toLowerCase()] = metric
            if metric.id
                metricsById[metric.id.toString().toLowerCase()] = metric

        collected = []
        seenIds = {}

        addMetricEntry = (metric) =>
            return if @.isUserMetricId(metric?.id) or @.isUserMetricId(metric?.externalId)
            entry = @.buildProjectMetricEntry(metric)
            if entry
                collected.push(entry)
                if metric.id?
                    seenIds[metric.id.toString().toLowerCase()] = true
                if metric.externalId?
                    seenIds[metric.externalId.toLowerCase()] = true

        projectOrder = @localConfig?.projectMetricsOrder
        unless angular.isArray(projectOrder) and projectOrder.length
            projectOrder = @metricsConfig.projectMetricsOrder or []
        for metricId in projectOrder
            normalizedId = metricId.toLowerCase()
            metric = metricsById[normalizedId]
            unless metric
                metric = _.find metricsArray, (candidate) =>
                    @.matchesConfiguredMetric(metricId, candidate.id, candidate.externalId, false)
                unless metric
                    continue

            classification = @.resolveMetricClassificationValue(metric)
            if classification is 'hidden'
                continue
            if classification is 'team'
                continue

            globalHidden = false
            if @metricsConfig.metricClassifications?[normalizedId] is 'hidden'
                globalHidden = true
            else if metric.externalId and @metricsConfig.metricClassifications?[metric.externalId.toLowerCase()] is 'hidden'
                globalHidden = true

            if globalHidden and classification isnt 'project'
                continue

            addMetricEntry(metric)

        if @localConfig?.classification
            for metric in metricsArray when metric?
                classification = @.resolveMetricClassificationValue(metric)
                continue unless classification is 'project'
                normalizedMetricId = null
                if metric.id?
                    normalizedMetricId = metric.id.toString().toLowerCase()
                else if metric.externalId?
                    normalizedMetricId = metric.externalId.toLowerCase()
                if normalizedMetricId and seenIds[normalizedMetricId]
                    continue
                addMetricEntry(metric)



        context =
            metrics: collected
            rawMetrics: metricsArray
            project: @scope.project
            scope: @scope

        transformed = @metricsHooks.transformProjectMetrics(context)

        if transformed isnt undefined and angular.isArray(transformed)
            finalMetrics = transformed
        else if angular.isArray(context.metrics)
            finalMetrics = context.metrics
        else
            finalMetrics = collected

        return @.scaleProjectMetricsByProjectMax(finalMetrics)

    resolveMetricCategoryColor: (categoryName, percentValue) ->
        return null unless categoryName?
        key = @.normalizeCategoryKey(categoryName)
        palette = if key then @metricsCategoryPalettes?[key] else null
        return null unless palette? and palette.length

        percent = Number(percentValue)
        percent = 0 unless isFinite(percent)
        ratio = Math.max(0, percent) / 100

        matchedColor = null

        for item in palette when item?.upperThreshold? and isFinite(item.upperThreshold)
            if ratio <= item.upperThreshold + 1e-9
                matchedColor = item.color
                break

        unless matchedColor?
            matchedColor = (palette[palette.length - 1]?.color) or palette[0]?.color

        matchedColor or null

    buildMetricCategorySegments: (categoryName) ->
        return null unless categoryName?
        key = @.normalizeCategoryKey(categoryName)
        palette = if key then @metricsCategoryPalettes?[key] else null
        return null unless palette? and palette.length

        segments = []
        lastThreshold = 0

        for entry in palette when entry?
            upper = Number(entry.upperThreshold)
            continue unless isFinite(upper)

            clamped = Math.max(lastThreshold, Math.min(Math.max(upper, 0), 1))
            segmentRatio = clamped - lastThreshold
            continue unless segmentRatio > 0

            segments.push({
                color: entry.color or "#2563EB"
                value: segmentRatio
                upperThreshold: clamped
            })

            lastThreshold = clamped

        if lastThreshold < 1
            remainderRatio = 1 - lastThreshold
            if remainderRatio > 0
                fallbackColor = palette[palette.length - 1]?.color or "#CBD5F5"
                segments.push({
                    color: fallbackColor
                    value: remainderRatio
                    upperThreshold: 1
                })

        if segments.length then segments else null

    isUserMetricId: (metricId) ->
        return false unless metricId?

        lowerId = metricId.toString().toLowerCase()
        classification = @.resolveLocalClassification(metricId)
        prefixes = [
            "assignedtasks_"
            "closedtasks_"
            "completedtasks_"
            "commits_"
            "modifiedlines_"
            "completedus_"
            "totalus_"
            "tasksratio_"
        ]
        isUserPattern = prefixes.some (prefix) -> lowerId.indexOf(prefix) is 0

        # Allow explicit overrides: a metric explicitly classified as project should
        # never be treated as a user-scoped metric. For team classification, only
        # mark it as user-scoped when it matches one of the known user patterns.
        if classification is 'project'
            return false

        if classification is 'team'
            return isUserPattern

        return isUserPattern
    
    resolveMetricUserContext: (metric) ->
        return null unless metric?

        pickValue = (obj, keys) ->
            return null unless obj?
            for key in keys when obj[key]?
                value = obj[key]
                if typeof value is "string"
                    trimmed = value.trim()
                    return trimmed if trimmed.length
                else if value?
                    return value
            null

        username = pickValue(metric, ["student", "user", "username", "owner"])
        displayName = pickValue(metric, ["student_display", "studentDisplay", "user_display", "userDisplay", "displayName"])

        username ?= pickValue(metric.metadata, ["student", "user", "username"])
        displayName ?= pickValue(metric.metadata, ["student_display", "studentDisplay", "user_display", "userDisplay", "displayName"])

        if !username and metric.id? and @.isUserMetricId(metric.id)
            parts = metric.id.toString().split("_")
            if parts.length > 1
                username = parts.slice(1).join("_")

        displayName ?= username

        return null unless username or displayName

        {
            username: username
            displayName: displayName
        }

    buildMetricDisplayGroups: (rawMetrics) ->
        groups =
            project: []
            team: []

        return groups unless angular.isArray(rawMetrics) and rawMetrics.length

        projectBuckets = {}
        teamBuckets = {}
        projectUnassigned = []
        teamUnassigned = []

        pushMetric = (bucket, name, entry) ->
            bucket[name] ?= []
            bucket[name].push(angular.copy(entry))

        for metric in rawMetrics when metric?
            classificationOverride = @.resolveMetricClassificationValue(metric)
            normalizedMetricId = if metric.id? then metric.id.toString().toLowerCase() else null
            normalizedExternalId = if metric.externalId? then metric.externalId.toLowerCase() else null
            isUserMetric = @.isUserMetricId(normalizedMetricId) or @.isUserMetricId(normalizedExternalId)
            if classificationOverride is 'hidden'
                continue
            
            # Check global configuration classification
            globalHidden = false
            if normalizedMetricId and @metricsConfig.metricClassifications?[normalizedMetricId] is 'hidden'
                globalHidden = true
            if normalizedExternalId and @metricsConfig.metricClassifications?[normalizedExternalId] is 'hidden'
                globalHidden = true
            if globalHidden and classificationOverride not in ['project', 'team']
                continue

            # Determine classification based on configuration
            isProjectConfigured = false
            isTeamConfigured = false

            # Check Project Config
            projectOrderConfig = @localConfig?.projectMetricsOrder
            unless angular.isArray(projectOrderConfig) and projectOrderConfig.length
                projectOrderConfig = @metricsConfig.projectMetricsOrder

            if projectOrderConfig
                for pMetric in projectOrderConfig
                    if @.matchesConfiguredMetric(pMetric, metric.id, metric.externalId, false)
                        isProjectConfigured = true
                        break

            # Check Team Config
            teamOrderConfig = @localConfig?.teamMetricsOrder
            unless angular.isArray(teamOrderConfig) and teamOrderConfig.length
                teamOrderConfig = @metricsConfig.teamMetricsOrder
            if teamOrderConfig
                for tMetric in teamOrderConfig
                    if @.matchesConfiguredMetric(tMetric, metric.id, metric.externalId, true)
                        isTeamConfigured = true
                        break
            
            if classificationOverride is 'project'
                isProjectConfigured = true
                isTeamConfigured = false
            else if classificationOverride is 'team'
                isTeamConfigured = true
                isProjectConfigured = false

            # Skip metrics that are not configured for any dashboard slot
            continue unless isProjectConfigured or isTeamConfigured

            # Only keep user-scoped metrics when they are explicitly enabled for the team dashboard
            if isUserMetric and !isTeamConfigured
                continue

            normalizedValue = @.normalizeMetricValue(metric.value)
            ratioValue = Math.max(0, Math.min(normalizedValue / 100, 1))
            userContext = @.resolveMetricUserContext(metric)

            entry =
                id: metric.id or metric.name
                label: metric.name or @.formatMetricLabel(metric.id)
                ratio: ratioValue
                formattedRatio: Number(ratioValue or 0).toFixed(2)
                description: metric.description
                rawValue: normalizedValue
                raw: metric
                user: userContext?.username
                userDisplayName: userContext?.displayName

            # For user metrics, prefer the metric name which typically contains the full user name
            # Example: "Clara Yiní López Vila modified lines" instead of "claraylv4 · Clara..."
            if @.isUserMetricId(entry.id) and userContext?
                # If metric.name exists, use it directly as it already contains the full name
                if metric.name and typeof metric.name is "string" and metric.name.trim().length > 0
                    entry.label = metric.name
                else
                    # Fallback: use displayName if available, otherwise format the metric id
                    displayLabel = userContext.displayName
                    if displayLabel and typeof displayLabel is "string" and displayLabel.trim().length > 0
                        entry.label = displayLabel
                    else
                        entry.label = @.formatMetricLabel(metric.id)

            # Pol Alcoverro added: Resolve colors for gauges
            categoryName = metric.categoryName or metric.category_name or metric.category?.name or metric.category
            # If no explicit category name, try to use the first quality factor if available
            if !categoryName and angular.isArray(metric.qualityFactors) and metric.qualityFactors.length > 0
                categoryName = metric.qualityFactors[0]

            entry.categoryColor = @.resolveMetricCategoryColor(categoryName, normalizedValue)
            entry.categorySegments = @.buildMetricCategorySegments(categoryName)
            
            # For internal provider, if no category color was resolved, use value-based color
            # Use ratioValue * 100 to get the percentage for color calculation
            if @metricsProvider is "internal" and not entry.categoryColor
                percentForColor = ratioValue * 100
                entry.categoryColor = @.getInternalGaugeColor(percentForColor)
            
            if isProjectConfigured
                if angular.isArray(metric.qualityFactors) and metric.qualityFactors.length > 0
                    for factorName in metric.qualityFactors when factorName
                        pushMetric(projectBuckets, factorName, entry)
                else
                    projectUnassigned.push(angular.copy(entry))

            if isTeamConfigured
                if angular.isArray(metric.qualityFactors) and metric.qualityFactors.length > 0
                    for factorName in metric.qualityFactors when factorName
                        pushMetric(teamBuckets, factorName, entry)
                else
                    teamUnassigned.push(angular.copy(entry))

        groups.project = @.convertMetricBucketsToGroups(projectBuckets, projectUnassigned, false)
        groups.team = @.convertMetricBucketsToGroups(teamBuckets, teamUnassigned, true)

        groups

    convertMetricBucketsToGroups: (buckets, unassignedList, isTeam) ->
        result = []

        for own bucketName, metricsList of buckets
            continue unless angular.isArray(metricsList) and metricsList.length > 0
            sortedMetrics = metricsList.slice().sort (a, b) ->
                aLabel = (a?.label or "").toString().toLowerCase()
                bLabel = (b?.label or "").toString().toLowerCase()
                if aLabel < bLabel then -1 else if aLabel > bLabel then 1 else 0

            label = @.formatMetricCategoryLabel(bucketName)
            result.push({
                id: "#{if isTeam then 'team' else 'project'}::#{bucketName}"
                name: bucketName
                label: label
                metrics: sortedMetrics
            })

        result.sort (a, b) ->
            aLabel = (a?.label or "").toString().toLowerCase()
            bLabel = (b?.label or "").toString().toLowerCase()
            if aLabel < bLabel then -1 else if aLabel > bLabel then 1 else 0

        if angular.isArray(unassignedList) and unassignedList.length > 0
            sortedFallback = unassignedList.slice().sort (a, b) ->
                aLabel = (a?.label or "").toString().toLowerCase()
                bLabel = (b?.label or "").toString().toLowerCase()
                if aLabel < bLabel then -1 else if aLabel > bLabel then 1 else 0

            label = if @translate?.instant?
                @translate.instant("METRICS.METRIC_GROUP_UNASSIGNED")
            else
                "Metrics not associated to any factor"

            result.push({
                id: "#{if isTeam then 'team' else 'project'}::uncategorized"
                name: "__uncategorized__"
                label: label
                metrics: sortedFallback
            })

        result

    buildProjectMetricEntry: (metric) ->
        return null unless metric

        normalizedValue = @.normalizeMetricValue(metric.value)
        numericValue = if isNaN(normalizedValue) then 0 else normalizedValue
        ratioValue = Math.max(0, numericValue / 100)
        ratioValue = Math.min(1, ratioValue)

        # Use value_description if provided to avoid rounding issues, but keep normalized fallback
        preciseValue = numericValue
        rawDescription = metric.value_description or metric.valueDescription
        if (preciseValue is 0 or !isFinite(preciseValue)) and typeof rawDescription is "string"
            descriptionNumber = parseFloat(rawDescription)
            if typeof descriptionNumber is "number" and !isNaN(descriptionNumber)
                preciseValue = Math.max(0, descriptionNumber * 100)

        roundedValue = Math.round(numericValue)
        formattedPrecise = Number(preciseValue or 0).toFixed(2)

        categoryName = metric.categoryName or metric.category_name or metric.category?.name or metric.category
        # If no explicit category name, try to use the first quality factor if available
        if !categoryName and angular.isArray(metric.qualityFactors) and metric.qualityFactors.length > 0
            categoryName = metric.qualityFactors[0]
        
        categoryColor = @.resolveMetricCategoryColor(categoryName, preciseValue or numericValue)
        categorySegments = @.buildMetricCategorySegments(categoryName)
        
        # For internal provider, if no category color was resolved, use value-based color
        # Use ratioValue * 100 to get the percentage for color calculation
        if @metricsProvider is "internal" and not categoryColor
            percentForColor = ratioValue * 100
            categoryColor = @.getInternalGaugeColor(percentForColor)

        return {
            id: metric.id
            name: metric.name or metric.id
            description: metric.description or ""
            value: numericValue
            absoluteValue: numericValue
            displayValueRounded: roundedValue
            displayValuePrecise: formattedPrecise
            absoluteDisplayValueRounded: roundedValue
            absoluteDisplayValuePrecise: formattedPrecise
            ratioValue: ratioValue
            ratioDisplayValueRounded: Math.round(ratioValue * 100) / 100
            ratioDisplayValuePrecise: Number(ratioValue or 0).toFixed(2)
            minLabel: "0%"
            maxLabel: "100%"
            qualityFactor: if angular.isArray(metric.qualityFactors) and metric.qualityFactors.length > 0 then metric.qualityFactors[0] else null
            raw: metric
            categoryName: categoryName
            categoryColor: categoryColor
            categorySegments: categorySegments
        }
    
    scaleProjectMetricsByProjectMax: (metricsArray) ->
        return metricsArray unless angular.isArray(metricsArray) and metricsArray.length > 0

        absoluteValues = []

        for metric in metricsArray when metric?
            absolute = metric.absoluteValue

            if typeof absolute isnt "number" or !isFinite(absolute)
                parsed = parseFloat(absolute)
                absolute = if isNaN(parsed) then null else parsed

            if typeof absolute isnt "number" or !isFinite(absolute)
                fallback = parseFloat(metric?.value)
                absolute = if isNaN(fallback) then null else fallback

            if typeof absolute is "number" and isFinite(absolute) and absolute isnt undefined
                absoluteValues.push(Math.max(0, absolute))

        return metricsArray unless absoluteValues.length

        maxValue = Math.max.apply(Math, absoluteValues)
        return metricsArray unless maxValue > 0

        for metric in metricsArray when metric?
            absolute = metric.absoluteValue

            if typeof absolute isnt "number" or !isFinite(absolute)
                parsed = parseFloat(absolute)
                absolute = if isNaN(parsed) then 0 else parsed

            unless typeof absolute is "number" and isFinite(absolute)
                fallback = parseFloat(metric?.value)
                absolute = if isNaN(fallback) then 0 else fallback

            absolute = Math.max(0, absolute or 0)

            ratio = if maxValue > 0 then absolute / maxValue else 0
            relativePercent = ratio * 100
            relativePercent = Math.max(0, relativePercent)
            relativePercent = Math.round(relativePercent * 100) / 100

            metric.relativePercent = relativePercent
            metric.maxReferenceValue = maxValue
            metric.value = relativePercent
            metric.displayValueRounded = Math.round(relativePercent)
            # Modificado por Pol Alcoverro
            metric.displayValuePrecise = String(Math.round(relativePercent))

        metricsArray
    
    # Prepare pie chart for hours distribution
    prepareHoursPieData: (hoursData) ->
        return null unless hoursData
        
        labels = []
        values = []
        chartColors = []
        borderColors = []

        if typeof hoursData is "object"
            try
                @.registerUserColors(Object.keys(hoursData))
            catch error
                console.warn("Unable to register user colors for hours data:", error)
        
        for student, data of hoursData
            labels.push(student)
            value = if typeof data == 'object' then (data.value || 0) else data
            values.push(value)
            colorPalette = @.resolveUserColor(student)
            solidColor = colorPalette?.solid or colorPalette?.fill or 'rgba(99, 102, 241, 0.7)'
            chartColors.push(solidColor)
            borderColors.push(colorPalette?.border or '#ffffff')
        
        return {
            labels: labels
            values: values
            colors: chartColors
            borderColors: borderColors
        }

    buildStudentsOverallRadar: (usersList) ->
        return null unless usersList and usersList.length > 0

        # Para el proveedor interno usamos métricas que realmente existen (tareas/US)
        if @metricsProvider is "internal"
            return @.buildInternalStudentsRadar(usersList)
        
        assignedLabel = @translate?.instant?("METRICS.RADAR_LABEL_ASSIGNED_TASKS") or "Assigned Tasks"
        commitsLabel = @translate?.instant?("METRICS.RADAR_LABEL_COMMITS") or "Commits"
        closedLabel = @translate?.instant?("METRICS.CLOSED_TASKS_LABEL") or "Closed Tasks"
        
        datasets = []
        @.registerUserColors(usersList)
        
        for user in usersList
            colorPalette = @.resolveUserColor(user)
            borderColor = colorPalette?.border or '#3B82F6'
            areaColor = colorPalette?.fill or 'rgba(59, 130, 246, 0.26)'
            
            assignedTasks = Math.max(0, Math.min(100, parseFloat(user.assignedTasks) or 0))
            commits = Math.max(0, Math.min(100, parseFloat(user.commits) or 0))
            closedTasks = Math.max(0, Math.min(100, parseFloat(user.closedTasks) or 0))
            
            dataset = {
                label: "#{user.displayName or user.username}"
                data: [assignedTasks, commits, closedTasks]
                backgroundColor: areaColor
                borderColor: borderColor
                borderWidth: 2
                pointBackgroundColor: borderColor
                pointBorderColor: '#fff'
                pointHoverBackgroundColor: '#fff'
                pointHoverBorderColor: borderColor
                pointRadius: 4
                pointHoverRadius: 6
            }
            
            datasets.push(dataset)
        
        return {
            labels: [assignedLabel, commitsLabel, closedLabel]
            datasets: datasets
        }

    buildInternalStudentsRadar: (usersList) ->
        return null unless usersList and usersList.length > 0

        tasksLabel = @translate?.instant?("METRICS.CLOSED_TASKS_LABEL") or "Closed Tasks"
        storiesLabel = @translate?.instant?("METRICS.RADAR_LABEL_COMPLETED_STORIES") or "Completed Stories"
        workloadLabel = @translate?.instant?("METRICS.RADAR_LABEL_ASSIGNED_TASKS") or "Assigned Tasks"

        datasets = []
        @.registerUserColors(usersList)

        for user in usersList
            colorPalette = @.resolveUserColor(user)
            borderColor = colorPalette?.border or '#3B82F6'
            areaColor = colorPalette?.fill or 'rgba(59, 130, 246, 0.26)'

            tasksPercent = Math.max(0, Math.min(100, parseFloat(user.tasksPercentage) or parseFloat(user.closedTasks) or 0))
            storiesPercent = Math.max(0, Math.min(100, parseFloat(user.usPercentage) or parseFloat(user.completedUS) or 0))
            workloadCount = Math.max(0, Math.min(100, parseFloat(user.assignedTasks) or 0))

            datasets.push({
                label: "#{user.displayName or user.username}"
                data: [tasksPercent, storiesPercent, workloadCount]
                backgroundColor: areaColor
                borderColor: borderColor
                borderWidth: 2
                pointBackgroundColor: borderColor
                pointBorderColor: '#fff'
                pointHoverBackgroundColor: '#fff'
                pointHoverBorderColor: borderColor
                pointRadius: 4
                pointHoverRadius: 6
            })

        {
            labels: [tasksLabel, storiesLabel, workloadLabel]
            datasets: datasets
        }

    buildClosedTasksComparison: (usersList) ->
        return null unless usersList and usersList.length > 0
        
        label = @translate?.instant?("METRICS.CLOSED_TASKS_LABEL") or "Closed Tasks"
        labels = []
        values = []
        barColors = []
        borderColors = []
        
        @.registerUserColors(usersList)

        for user in usersList
            labels.push(user.displayName or user.username)
            closedTasks = Number(parseFloat(user.closedTasks) or parseFloat(user.completedTasks) or 0) or 0
            values.push(Math.max(0, Math.min(100, closedTasks)))
            colorPalette = @.resolveUserColor(user)
            solidColor = colorPalette?.solid or colorPalette?.fill or 'rgba(59, 130, 246, 0.7)'
            barColors.push(solidColor)
            borderColors.push(colorPalette?.border or '#ffffff')
        
        return {
            labels: labels
            datasets: [{
                label: label
                data: values
                backgroundColor: barColors
                borderColor: borderColors
                borderWidth: 1
                borderRadius: 8
                borderSkipped: false
                maxBarThickness: 48
            }]
            options:
                plugins:
                    legend:
                        display: false
        }

    prepareStrategicIndicators: (indicators) ->
        return [] unless angular.isArray(indicators)
        
        processed = []
        
        for indicator in indicators
            continue unless indicator?.id?
            
            # Extract value (can be object with first/second or direct number)
            value = if indicator.value?.first?
                parseFloat(indicator.value.first)
            else if typeof indicator.value is 'number'
                parseFloat(indicator.value)
            else
                0
            
            # Convert to percentage (0-100)
            percentValue = value * 100
            percentValue = Math.max(0, Math.min(100, percentValue))
            
            # Get category label
            categoryLabel = indicator.value?.second or indicator.value_description or ""
            
            entry = {
                id: indicator.id
                name: indicator.name or indicator.id
                description: indicator.description or ""
                value: indicator.value
                displayValue: percentValue
                displayValueRounded: Math.round(percentValue)
                displayValuePrecise: percentValue.toFixed(2)
                categoryLabel: categoryLabel
                date: indicator.date
                rationale: indicator.rationale
                categories_description: indicator.categories_description
            }
            
            processed.push(entry)
        
        return processed

    prepareQualityFactors: (factors) ->
        return [] unless angular.isArray(factors)
        
        processed = []
        
        for factor in factors
            continue unless factor?.id?
            
            # Extract value (can be object with first/second or direct number)
            value = if factor.value?.first?
                parseFloat(factor.value.first)
            else if typeof factor.value is 'number'
                parseFloat(factor.value)
            else
                0
            
            # Convert to percentage (0-100)
            percentValue = value * 100
            percentValue = Math.max(0, Math.min(100, percentValue))
            
            # Assign color based on value for internal provider
            categoryColor = null
            if @metricsProvider is "internal"
                categoryColor = @.getInternalGaugeColor(percentValue)
            
            entry = {
                id: factor.id
                name: factor.name or factor.id
                description: factor.description or ""
                value: factor.value
                displayValue: percentValue
                displayValueRounded: Math.round(percentValue)
                displayValuePrecise: percentValue.toFixed(2)
                date: factor.date
                type: factor.type
                metrics: factor.metrics or []
                missingMetrics: factor.missingMetrics or []
                categoryColor: categoryColor
            }
            
            processed.push(entry)
        
        return processed
    
    # Returns color for internal gauges based on percentage value
    # Red (0-33%), Orange (34-66%), Green (67-100%)
    getInternalGaugeColor: (percentValue) ->
        if percentValue < 33
            return 'rgba(239, 68, 68, 0.9)'  # Red
        else if percentValue < 66
            return 'rgba(251, 191, 36, 0.9)'  # Orange
        else
            return 'rgba(34, 197, 94, 0.9)'   # Green

    loadInitialData: ->
        project = @.loadProject()
        configPromise = @.fetchProjectConfig()

        return @q.all([
            @q.when(project)
            configPromise
        ])

    resolveErrorKey: (value, defaultKey) ->
        return defaultKey unless value
        return value if value.indexOf("METRICS.") is 0
        slug = value.replace(/[^a-zA-Z0-9]/g, "_").toUpperCase()
        return "METRICS.ERROR_#{slug}"

    drawTestingCharts: =>
        @.drawRadarChart()
        @.drawSemicircleChart()

    drawRadarChart: ->
        canvas = document.getElementById("radarChart")
        return unless canvas
        
        # Wait for Chart.js to be available
        checkChart = =>
            if window.Chart?
                @.renderRadarWithChartJS(canvas)
            else
                setTimeout(checkChart, 100)
        
        checkChart()
    
    renderRadarWithChartJS: (canvas) ->
        ctx = canvas.getContext("2d")
        return unless ctx
        
        # Destroy existing chart if any
        if @testingRadarChart?
            @testingRadarChart.destroy()
        
        # Data from AMEP11ChopChop real metrics
        data = 
            labels: ["Tasks SD", "Commits SD", "Closed Tasks", "Modified Lines"]
            datasets: [
                {
                    label: 'Development Metrics'
                    data: [7, 19, 83, 0]
                    backgroundColor: 'rgba(52, 152, 219, 0.2)'
                    borderColor: 'rgba(52, 152, 219, 1)'
                    borderWidth: 3
                    pointBackgroundColor: 'rgba(52, 152, 219, 1)'
                    pointBorderColor: '#fff'
                    pointHoverBackgroundColor: '#fff'
                    pointHoverBorderColor: 'rgba(52, 152, 219, 1)'
                    pointRadius: 5
                    pointHoverRadius: 7
                }
            ]
        
        config = 
            type: 'radar'
            data: data
            options:
                responsive: true
                maintainAspectRatio: true
                scales:
                    r:
                        beginAtZero: true
                        min: 0
                        max: 100
                        ticks:
                            stepSize: 20
                            color: '#2c3e50'
                            font:
                                size: 11
                            callback: (value) -> "#{value}%"
                        pointLabels:
                            color: '#2c3e50'
                            font:
                                size: 12
                                weight: 'bold'
                        grid:
                            color: 'rgba(44, 62, 80, 0.15)'
                plugins:
                    legend:
                        display: false
                    tooltip:
                        callbacks:
                            label: (context) ->
                                "#{context.parsed.r}%"
        
        @testingRadarChart = new window.Chart(ctx, config)

    drawSemicircleChart: ->
        canvas = document.getElementById("semicircleChart")
        return unless canvas
        
        # Wait for Chart.js to be available
        checkChart = =>
            if window.Chart?
                @.renderSemicircleWithChartJS(canvas)
            else
                setTimeout(checkChart, 100)
        
        checkChart()
    
    ###
    # Created by: Pol Alcoverro
    # Description: Renders the semicircle gauge that paints the acceptance criteria indicator as a half moon.
    ###
    renderSemicircleWithChartJS: (canvas) ->
        ctx = canvas.getContext("2d")
        return unless ctx
        
        # Destroy existing chart if any
        if @testingSemicircleChart?
            @testingSemicircleChart.destroy()
        
        gaugeContext =
            defaultValue: 11
            data: @scope.metricsView?.data
            project: @scope.project
            scope: @scope

        resolvedValue = @metricsHooks.resolveGaugeValue(gaugeContext)

        if resolvedValue? and !isNaN(parseFloat(resolvedValue))
            value = Number(parseFloat(resolvedValue))
        else if gaugeContext.defaultValue? and !isNaN(parseFloat(gaugeContext.defaultValue))
            value = Number(parseFloat(gaugeContext.defaultValue))
        else
            value = 0
        
        value = Math.max(0, Math.min(100, value or 0))

        # Determine color based on value
        color = if value < 33
            "#f44336"  # Red
        else if value < 66
            "#ff9800"  # Orange
        else
            "#4caf50"  # Green
        
        config = 
            type: 'doughnut'
            data:
                datasets: [
                    {
                        data: [value, 100 - value]
                        backgroundColor: [
                            color
                            'rgba(220, 220, 220, 0.2)'
                        ]
                        borderWidth: 0
                        circumference: 180
                        rotation: 270
                        cutout: '70%'
                        borderRadius: 8
                    }
                ]
            options:
                responsive: true
                maintainAspectRatio: true
                aspectRatio: 2
                plugins:
                    legend:
                        display: false
                    tooltip:
                        enabled: false
            plugins: [
                {
                    id: 'gaugeCenterText'
                    afterDatasetDraw: (chart) =>
                        ctx = chart.ctx
                        width = chart.width
                        height = chart.height
                        
                        # Draw value in center
                        ctx.save()
                        ctx.font = "bold 48px Arial"
                        ctx.fillStyle = "#2c3e50"
                        ctx.textAlign = "center"
                        ctx.textBaseline = "middle"
                        ctx.fillText("#{value}%", width / 2, height / 2 - 20)
                        
                        # Draw label
                        ctx.font = "14px Arial"
                        ctx.fillStyle = "#7f8c8d"
                        ctx.fillText("Strategic Indicators", width / 2, height / 2 + 20)
                        
                        # Draw scale labels
                        ctx.font = "11px Arial"
                        ctx.fillStyle = "#95a5a6"
                        ctx.textAlign = "left"
                        ctx.fillText("0%", 30, height / 2 + 5)
                        ctx.textAlign = "right"
                        ctx.fillText("100%", width - 30, height / 2 + 5)
                        
                        # Draw range labels
                        ctx.font = "bold 10px Arial"
                        ctx.textAlign = "center"
                        
                        ctx.fillStyle = "#f44336"
                        ctx.fillText("Low", width / 2 - 80, height / 2 + 50)
                        
                        ctx.fillStyle = "#ff9800"
                        ctx.fillText("Medium", width / 2, height / 2 + 50)
                        
                        ctx.fillStyle = "#4caf50"
                        ctx.fillText("High", width / 2 + 80, height / 2 + 50)
                        
                        ctx.restore()
                }
            ]
        
        @testingSemicircleChart = new window.Chart(ctx, config)

    ##########################################################################
    # Historical Data Processing Functions
    ##########################################################################
    
    processHistoricalData: (historicalData) ->
        """
        Process historical metrics data from LD backend into chart-ready format
        The LD backend returns data already organized and processed:
        {
            userMetrics: { metricKey: [{date, value, name, username}, ...] },
            projectMetrics: { metricKey: [{date, value, name}, ...] },
            strategicMetrics: { metricKey: [{date, value, name}, ...] },
            qualityFactors: { metricKey: [{date, value, name}, ...] }
        }
        """
        
        # Check if historicalData is the expected object with userMetrics, projectMetrics, etc.
        if !historicalData or typeof historicalData isnt 'object'
            console.warn("No historical data to process or invalid format")
            return {
                userMetrics: {}
                projectMetrics: {}
                strategicMetrics: {}
                qualityFactors: {}
            }
        
        # Extract the raw data from LD backend
        userMetricsRaw = historicalData.userMetrics or {}
        projectMetricsRaw = historicalData.projectMetrics or {}
        strategicMetricsRaw = historicalData.strategicMetrics or {}
        qualityFactorsRaw = historicalData.qualityFactors or {}
        
        # Convert raw data arrays into chart-ready format for tg-area-chart directive
        result = {
            userMetrics: @convertRawMetricsToCharts(userMetricsRaw, 'user')
            projectMetrics: @convertRawMetricsToCharts(projectMetricsRaw, 'project')
            strategicMetrics: @convertRawMetricsToCharts(strategicMetricsRaw, 'strategic')
            qualityFactors: @convertRawMetricsToCharts(qualityFactorsRaw, 'quality')
            raw: historicalData
        }
        
        return result
    
    convertRawMetricsToCharts: (metricsData, category) ->
        """
        Convert raw metrics arrays into Chart.js format for tg-area-chart
        Input: { metricKey: [{date, value, name, student?}, ...], ... }
        Output: { [key]: {labels: [...], datasets: [{...}], ...}, ... }
        """
        result = {}
        
        return result unless metricsData and typeof metricsData is 'object'
        
        for metricKey, dataPoints of metricsData
            continue unless angular.isArray(dataPoints) and dataPoints.length > 0
            
            labels = []
            values = []
            metricName = metricKey
            
            # Extract dates, values, and metric name from data points
            for point in dataPoints when point?
                # Get date/timestamp
                date = point.date or point.timestamp or point.created_at
                labels.push(date) if date
                
                # Get value - handle nested and direct values
                value = 0
                if point.value?
                    if typeof point.value is 'number'
                        value = point.value
                    else if typeof point.value is 'string'
                        parsed = parseFloat(point.value)
                        value = if !isNaN(parsed) then parsed else 0
                    else if typeof point.value is 'object'
                        if point.value.first?
                            value = parseFloat(point.value.first)
                        else if point.value.value?
                            value = if typeof point.value.value is 'number' then point.value.value else parseFloat(point.value.value)
                
                values.push(value)
                
                # Get metric name from first point if available
                if point.name and metricName is metricKey
                    metricName = point.name
            
            # Skip if no valid data
            if labels.length is 0 or values.length is 0
                continue
            
            # Create display label
            displayLabel = if metricName and metricName isnt metricKey
                metricName
            else
                @formatMetricLabel(metricKey)
            
            # Build chart dataset
            maxValue = Math.max.apply(Math, values)

            chartDataset = {
                label: displayLabel
                data: values
                borderColor: '#44C2C2'
                backgroundColor: 'rgba(68, 194, 194, 0.18)'
                fill: true
                tension: 0.3
                borderWidth: 2
                pointRadius: 2.5
                pointHoverRadius: 4
                pointBorderWidth: 1
                pointBackgroundColor: '#44C2C2'
                pointBorderColor: '#ffffff'
            }
            
            # Format as Chart.js structure for tg-area-chart
            result[metricKey] = {
                title: displayLabel
                labels: labels
                datasets: [chartDataset]
                yAxisMax: if maxValue <= 1 then 1.08 else null
                showLegend: false
                metricCategory: category
            }
        
        return result
    
    
    buildTeamHistoricalData: (userMetricsRaw) ->
        result =
            users: []
            chartsByUser: {}
            chartsByCategory: {}

        return result unless userMetricsRaw? and typeof userMetricsRaw is "object"

        userSet = {}

        mergedMetrics = @.mergeHistoricalMetricSeries(userMetricsRaw)

        for own normalizedId, bundle of mergedMetrics
            metricId = bundle?.metricId
            dataPoints = bundle?.dataPoints
            continue unless metricId? and angular.isArray(dataPoints) and dataPoints.length

            category = @.identifyHistoricalMetricCategory(metricId)
            continue unless category

            groupedByStudent = {}

            for point in dataPoints when point?
                student = point.student or point.username or point.name or point.user
                continue unless student? and student.toString().trim().length
                normalizedStudent = student.toString().trim()
                groupedByStudent[normalizedStudent] ?= []
                groupedByStudent[normalizedStudent].push(point)

            for student, studentPoints of groupedByStudent
                continue unless angular.isArray(studentPoints) and studentPoints.length

                collection = @.buildHistoricalEntryCollection(student, category, metricId, studentPoints)
                continue unless collection

                userSet[student] = true

                result.chartsByUser[student] ?= {}
                result.chartsByUser[student][category] = collection

                result.chartsByCategory[category] ?= {}
                result.chartsByCategory[category][student] = collection

        result.users = Object.keys(userSet).sort (a, b) ->
            a.localeCompare(b)

        return result

    buildHistoricalEntryCollection: (student, category, metricId, dataPoints) ->
        return null unless angular.isArray(dataPoints) and dataPoints.length

        entries = []
        metricName = null

        for point in dataPoints when point?
            metricName ?= point.name if point.name?

            rawLabel = point.date or point.timestamp or point.created_at or point.createdAt or point.evaluation_date or point.evaluationDate
            value = @.extractHistoricalPointValue(point)
            continue unless rawLabel? and value?

            timestamp = Date.parse(rawLabel)
            label = if !isNaN(timestamp) then new Date(timestamp).toISOString().slice(0, 10) else rawLabel

            entries.push({
                label: label
                timestamp: if isNaN(timestamp) then null else timestamp
                value: value
                raw: point
            })

        return null unless entries.length

        entries.sort (a, b) ->
            if a.timestamp? and b.timestamp?
                return a.timestamp - b.timestamp
            if a.timestamp? and !b.timestamp?
                return -1
            if !a.timestamp? and b.timestamp?
                return 1
            return a.label.localeCompare(b.label)

        {
            student: student
            category: category
            metricId: metricId
            metricName: metricName
            entries: entries
        }

    normalizeFilterDate: (value) ->
        return null unless value?
        if value instanceof Date
            timestamp = value.getTime()
            return null if isNaN(timestamp)
            return timestamp
        if typeof value is "number" and !isNaN(value)
            return value
        parsed = Date.parse(value)
        return null if isNaN(parsed)
        parsed

    filterHistoricalEntries: (entries, dateFrom, dateTo) ->
        return [] unless angular.isArray(entries)

        fromTimestamp = @.normalizeFilterDate(dateFrom)
        toTimestamp = @.normalizeFilterDate(dateTo)

        return entries unless fromTimestamp? or toTimestamp?

        if toTimestamp?
            # Include the entire to-date day
            toTimestamp += 24 * 60 * 60 * 1000 - 1

        entries.filter (entry) ->
            include = true
            if fromTimestamp? and entry.timestamp?
                include = false if entry.timestamp < fromTimestamp
            if include and toTimestamp? and entry.timestamp?
                include = false if entry.timestamp > toTimestamp
            include

    buildChartDatasetFromEntries: (student, category, entries) ->
        return null unless angular.isArray(entries) and entries.length

        labels = []
        values = []

        for entry in entries
            labels.push(entry.label)
            numericValue = Number(entry.value)
            values.push(if isNaN(numericValue) then 0 else numericValue)

        colorPalette = @.resolveUserColor(student)

        dataset = {
            label: student
            data: values
            borderColor: colorPalette.border
            backgroundColor: colorPalette.fill
            pointBackgroundColor: colorPalette.border
            pointBorderColor: "#ffffff"
            pointHoverBackgroundColor: colorPalette.border
            pointHoverBorderColor: "#ffffff"
            fill: true
            tension: 0.35
            borderWidth: 2
            pointRadius: 2.5
            pointHoverRadius: 4
            pointBorderWidth: 1
        }

        axisConfig = @.resolveHistoricalAxisConfig(category, values)

        {
            title: student
            labels: labels
            datasets: [dataset]
            showLegend: false
            yAxisMax: axisConfig.max
            yAxisStep: axisConfig.step
            isPercentage: axisConfig.isPercentage
            metricCategory: category
        }

    normalizeHistoricalMetricId: (metricId) ->
        return "" unless metricId?
        metricId.toString().toLowerCase().replace(/[-\s]+/g, "_")

    historicalPointKey: (point) ->
        return null unless point?
        timestamp = @.extractHistoricalPointTimestamp(point)
        if timestamp?
            return "ts::#{timestamp}"

        label = point?.date or point?.label or point?.timestamp or point?.created_at or point?.createdAt
        if label?
            return "label::#{label}"

        try
            return "raw::#{JSON.stringify(point)}"
        catch error
            null

    deduplicateAndSortHistoricalPoints: (points) ->
        return [] unless angular.isArray(points)

        seen = {}
        cleaned = []

        for point in points when point?
            key = @.historicalPointKey(point)
            continue unless key?
            continue if seen[key]
            seen[key] = true
            cleaned.push(point)

        cleaned.sort (a, b) =>
            tsA = @.extractHistoricalPointTimestamp(a)
            tsB = @.extractHistoricalPointTimestamp(b)

            if tsA? and tsB?
                return 0 if tsA is tsB
                return tsA - tsB
            if tsA?
                return -1
            if tsB?
                return 1

            labelA = @.historicalPointKey(a) or ""
            labelB = @.historicalPointKey(b) or ""
            labelA.localeCompare(labelB)

        cleaned

    mergeHistoricalMetricSeries: (metricsRaw) ->
        merged = {}
        return merged unless metricsRaw? and typeof metricsRaw is "object"

        for own metricId, dataPoints of metricsRaw
            continue unless angular.isArray(dataPoints) and dataPoints.length

            normalizedId = @.normalizeHistoricalMetricId(metricId)
            entry = merged[normalizedId]
            pointsCopy = dataPoints.slice()

            if entry?
                entry.dataPoints = entry.dataPoints.concat(pointsCopy)
                entry.sourceIds.push(metricId)
            else
                merged[normalizedId] = {
                    metricId: metricId
                    dataPoints: pointsCopy
                    sourceIds: [metricId]
                }

        for own normalizedId, entry of merged
            entry.dataPoints = @.deduplicateAndSortHistoricalPoints(entry.dataPoints)

        merged

    extractHistoricalPointValue: (point) ->
        return null unless point?

        candidates = [
            point.value
            point.metric_value
            point.metricValue
            point.score
            point.percentage
        ]

        for candidate in candidates when candidate?
            normalized = @.normalizeMetricValue(candidate)
            if typeof normalized is "number" and !isNaN(normalized)
                return normalized

        return null

    extractHistoricalPointTimestamp: (point) ->
        return null unless point?

        raw = point.date or point.timestamp or point.created_at or point.createdAt or point.evaluation_date or point.evaluationDate
        return null unless raw?

        if raw instanceof Date
            timestamp = raw.getTime()
            return null if isNaN(timestamp)
            return timestamp

        if typeof raw is "number" and !isNaN(raw)
            return raw

        parsed = Date.parse(raw)
        return null if isNaN(parsed)
        parsed

    identifyHistoricalMetricCategory: (metricId) ->
        return null unless metricId?

        normalized = metricId.toString().toLowerCase()

        if normalized.indexOf("assignedtasks_") isnt -1 or normalized.indexOf("tasksratio_") isnt -1
            return "tasks"
        if normalized.indexOf("closedtasks_") isnt -1 or normalized.indexOf("completedtasks_") isnt -1
            return "closed_tasks"
        if normalized.indexOf("modifiedlines_") isnt -1
            return "modified_lines"
        if normalized.indexOf("commits_") isnt -1
            return "commits"

        null

    resolveUserColor: (seed) ->
        defaultColor = @userColorPalette?[0] or @.prepareColorFromHex("#6366F1")
        identifier = @.normalizeUserIdentifier(seed)
        return defaultColor unless identifier?.length

        key = @.normalizeUserColorKey(identifier)
        return defaultColor unless key.length

        stored = @userColorAssignments?[key]
        if stored?
            return stored

        aliasKey = @userColorAliasIndex?[key]
        if aliasKey? and @userColorAssignments?[aliasKey]
            return @userColorAssignments[aliasKey]

        similarKey = @.findSimilarUserColorKey(key)
        if similarKey? and @userColorAssignments?[similarKey]
            @userColorAliasIndex ?= {}
            @userColorAliasIndex[key] = similarKey
            return @userColorAssignments[similarKey]

        color = @.assignColorForKey(key)
        color ? defaultColor

    registerUserColors: (users) ->
        return unless users?

        candidates = []

        if angular.isArray(users)
            for user in users when user?
                identifier = @.normalizeUserIdentifier(user)
                continue unless identifier?.length
                key = @.normalizeUserColorKey(identifier)
                continue unless key.length
                candidates.push({
                    identifier: identifier
                    key: key
                    aliases: @.collectUserAliasKeys(user, key)
                })
        else if typeof users is "object"
            for own attr, value of users when value?
                identifier = @.normalizeUserIdentifier(value) or @.normalizeUserIdentifier(attr)
                continue unless identifier?.length
                key = @.normalizeUserColorKey(identifier)
                continue unless key.length
                aliasList = []
                if typeof value is "object" and !angular.isArray(value)
                    aliasList = @.collectUserAliasKeys(value, key)
                else
                    aliasFromAttr = @.normalizeUserColorKey(attr)
                    if aliasFromAttr.length and aliasFromAttr isnt key
                        aliasList.push(aliasFromAttr)
                candidates.push({
                    identifier: identifier
                    key: key
                    aliases: aliasList
                })

        candidates.sort (a, b) ->
            a.identifier.localeCompare(b.identifier)

        seen = {}
        for candidate in candidates
            continue unless candidate?.key
            continue if seen[candidate.key]
            seen[candidate.key] = true
            unless @userColorAssignments?[candidate.key]
                @.assignColorForKey(candidate.key)
            else
                @userColorAliasIndex ?= {}
                @userColorAliasIndex[candidate.key] ?= candidate.key
            @.registerAliasKeys(candidate.aliases, candidate.key)

    resetUserColorAssignments: ->
        @userColorAssignments = {}
        @userColorIndex = 0
        @userColorAliasIndex = {}

    assignColorForKey: (key) ->
        return @userColorAssignments[key] if @userColorAssignments?[key]
        color = @.nextUserColor()
        @userColorAssignments[key] = color
        @userColorAliasIndex ?= {}
        @userColorAliasIndex[key] = key
        color

    nextUserColor: ->
        basePalette = @userColorPalette or []
        if @userColorIndex < basePalette.length
            colorTemplate = basePalette[@userColorIndex]
            @userColorIndex += 1
            if angular?.copy?
                return angular.copy(colorTemplate)
            try
                return JSON.parse(JSON.stringify(colorTemplate))
            catch error
                return colorTemplate

        hue = (@userColorIndex * 47) % 360
        @userColorIndex += 1
        @.generateColorFromHue(hue)

    buildUserColorPalette: ->
        # Pol Alcoverro - Paleta optimizada para equipos de 6-8 personas
        # Los primeros 8 colores están máximamente diferenciados para evitar confusión
        baseHex = [
            "#DC2626"  # 1. Rojo intenso
            "#2563EB"  # 2. Azul rey brillante
            "#059669"  # 3. Verde bosque
            "#F59E0B"  # 4. Ámbar/Naranja cálido
            "#9333EA"  # 5. Púrpura profundo
            "#0891B2"  # 6. Cyan/Turquesa
            "#7C3AED"  # 7. Violeta vivid
            "#65A30D"  # 8. Lima/Verde oliva
            "#6366F1"  # 9. Índigo
            "#F97316"  # 10. Naranja oscuro
            "#14B8A6"  # 11. Teal
            "#A855F7"  # 12. Violeta
            "#EF4444"  # 13. Rojo
            "#0EA5E9"  # 14. Sky blue
            "#22C55E"  # 15. Verde
            "#D946EF"  # 16. Magenta
            "#F43F5E"  # 17. Rosa
            "#3B82F6"  # 18. Azul medio
            "#10B981"  # 19. Verde esmeralda
            "#E53E3E"  # 20. Rojo claro
        ]

        baseHex.map (hex) => @.prepareColorFromHex(hex)

    normalizeUserIdentifier: (input) ->
        return "" unless input?

        if typeof input is "string"
            trimmed = input.toString().trim()
            return trimmed

        if typeof input is "object"
            candidates = [
                input.username
                input.identities?.TAIGA?.username
                input.identities?.GITHUB?.username
                input.displayName
                input.name
                input.fullName
                input.student
                input.user
                input.id
                input.email
            ]

            for candidate in candidates when candidate?
                value = candidate.toString().trim()
                return value if value.length

        ""

    normalizeUserColorKey: (identifier) ->
        return "" unless identifier?
        key = identifier.toString().trim().toLowerCase()
        try
            key = key.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
        catch error
            # normalize might not be available; ignore gracefully
            null
        slug = key.replace(/[\s\-]+/g, "_").replace(/[^a-z0-9_]/g, "")
        return slug if slug.length
        key

    collectUserAliasKeys: (user, canonicalKey = "") ->
        aliases = []
        return aliases unless user?

        if typeof user is "object"
            aliasCandidates = [
                user.displayName
                user.name
                user.fullName
                user.student
                user.user
                user.id
                user.email
            ]

            seen = {}
            for candidate in aliasCandidates when candidate?
                aliasKey = @.normalizeUserColorKey(candidate)
                continue unless aliasKey.length
                continue if canonicalKey? and aliasKey is canonicalKey
                continue if seen[aliasKey]
                seen[aliasKey] = true
                aliases.push(aliasKey)
        else if typeof user is "string"
            aliasKey = @.normalizeUserColorKey(user)
            if aliasKey.length and aliasKey isnt canonicalKey
                aliases.push(aliasKey)

        aliases

    registerAliasKeys: (aliases, canonicalKey) ->
        return unless canonicalKey?
        return unless angular.isArray(aliases) and aliases.length

        @userColorAliasIndex ?= {}

        for aliasKey in aliases when aliasKey?
            continue unless aliasKey.length
            continue if aliasKey is canonicalKey
            existing = @userColorAliasIndex[aliasKey]
            if existing? and existing isnt canonicalKey
                continue
            @userColorAliasIndex[aliasKey] = canonicalKey

    findSimilarUserColorKey: (key) ->
        return null unless key?

        assignments = @userColorAssignments or {}

        for own existingKey, color of assignments when existingKey?
            continue unless typeof existingKey is "string"
            if key.indexOf(existingKey) isnt -1 or existingKey.indexOf(key) isnt -1
                return existingKey

        null

    prepareColorFromHex: (hex, fillAlpha = 0.26, solidAlpha = 0.74) ->
        rgb = @.hexToRgb(hex)

        unless rgb?
            return {
                border: hex
                fill: "rgba(99, 102, 241, #{fillAlpha})"
                solid: "rgba(99, 102, 241, #{solidAlpha})"
            }

        {
            border: hex
            fill: "rgba(#{rgb.r}, #{rgb.g}, #{rgb.b}, #{fillAlpha})"
            solid: "rgba(#{rgb.r}, #{rgb.g}, #{rgb.b}, #{solidAlpha})"
        }

    hexToRgb: (hex) ->
        return null unless typeof hex is "string"

        normalized = hex.replace("#", "")
        return null unless normalized.length in [3, 6]

        if normalized.length is 3
            normalized = normalized.split("").map((char) -> "#{char}#{char}").join("")

        intVal = parseInt(normalized, 16)
        return null if isNaN(intVal)

        r = (intVal >> 16) & 255
        g = (intVal >> 8) & 255
        b = intVal & 255

        {r, g, b}

    generateColorFromHue: (hue) ->
        hueValue = ((hue % 360) + 360) % 360
        rgb = @.hslToRgb(hueValue / 360, 0.62, 0.55)
        hex = @.rgbToHex(rgb[0], rgb[1], rgb[2])
        @.prepareColorFromHex(hex)

    hslToRgb: (h, s, l) ->
        h = Math.max(0, Math.min(1, h))
        s = Math.max(0, Math.min(1, s))
        l = Math.max(0, Math.min(1, l))

        if s is 0
            r = l
            g = l
            b = l
        else
            hue2rgb = (p, q, t) ->
                t += 1 if t < 0
                t -= 1 if t > 1
                if t < 1/6
                    return p + (q - p) * 6 * t
                if t < 1/2
                    return q
                if t < 2/3
                    return p + (q - p) * (2/3 - t) * 6
                p

            q = if l < 0.5 then l * (1 + s) else l + s - l * s
            p = 2 * l - q

            r = hue2rgb(p, q, h + 1/3)
            g = hue2rgb(p, q, h)
            b = hue2rgb(p, q, h - 1/3)

        [
            Math.round(r * 255)
            Math.round(g * 255)
            Math.round(b * 255)
        ]

    rgbToHex: (r, g, b) ->
        componentToHex = (value) ->
            clamped = Math.max(0, Math.min(255, Math.round(value)))
            hexComponent = clamped.toString(16)
            if hexComponent.length is 1
                "0#{hexComponent}"
            else
                hexComponent

        "#" + componentToHex(r) + componentToHex(g) + componentToHex(b)

    resolveHistoricalAxisConfig: (category, values) ->
        numericValues = []
        if angular.isArray(values)
            numericValues = values.filter (value) ->
                typeof value is "number" and !isNaN(value)

        maxValue = if numericValues.length then Math.max.apply(Math, numericValues) else 0

        percentageCategories = ["tasks", "closed_tasks", "modified_lines", "commits"]
        isPercentage = percentageCategories.indexOf(category) isnt -1

        config =
            isPercentage: isPercentage
            max: null
            step: null

        if isPercentage
            baseMax = 100
            adjustedMax = if maxValue > baseMax then Math.ceil(maxValue / 10) * 10 else baseMax
            config.max = adjustedMax
            config.step = 20

        return config

    metricCategoryLabelKey: (category) ->
        switch category
            when "tasks" then "METRICS.TEAM_HISTORICAL_METRIC_TASKS"
            when "closed_tasks" then "METRICS.TEAM_HISTORICAL_METRIC_CLOSED_TASKS"
            when "modified_lines" then "METRICS.TEAM_HISTORICAL_METRIC_MODIFIED_LINES"
            when "commits" then "METRICS.TEAM_HISTORICAL_METRIC_COMMITS"
            else null

    buildQualityFactorNamesMap: (metricsData) ->
        ###
        # Build a map from quality factor id to its display name
        # This allows showing "Modified Lines Contribution" instead of "modifiedlinescontribution"
        # 
        # The API returns data where each item in the main array is a quality factor with:
        # - id: "modifiedlinescontribution"
        # - name: "Modified Lines Contribution"
        # - metrics: [...] (nested individual metrics)
        #
        # Individual metrics have qualityFactors: ["modifiedlinescontribution"] (just the id)
        ###
        map = {}
        return map unless angular.isArray(metricsData)
        
        for item in metricsData when item?.id?
            itemId = item.id.toString().toLowerCase()
            hasName = item.name and typeof item.name is "string" and item.name.trim().length > 0
            
            # An item is a quality factor (parent) if:
            # 1. It has a 'metrics' property (array of child metrics), OR
            # 2. It does NOT have a 'qualityFactors' property (child metrics have this)
            hasMetricsArray = item.hasOwnProperty("metrics")
            hasQualityFactorsArray = angular.isArray(item.qualityFactors) and item.qualityFactors.length > 0
            isQualityFactor = hasMetricsArray or !hasQualityFactorsArray
            
            if hasName and isQualityFactor
                map[itemId] = item.name.trim()
                
            # Also process nested metrics to find any additional quality factor references
            if angular.isArray(item.metrics)
                for childMetric in item.metrics when childMetric?.qualityFactors?
                    # The qualityFactors array contains IDs, and the parent has the name
                    for factorId in childMetric.qualityFactors when factorId
                        normalizedFactorId = factorId.toString().toLowerCase()
                        # If we haven't mapped this factor yet, and the current item is the parent
                        if !map[normalizedFactorId] and itemId is normalizedFactorId and hasName
                            map[normalizedFactorId] = item.name.trim()
        
        return map

    formatMetricCategoryLabel: (category) ->
        return "" unless category?
        categoryStr = category.toString()
        
        # First, check if we have a known name from the quality factors map
        normalizedCategory = categoryStr.toLowerCase()
        
        if @qualityFactorNamesMap? and @qualityFactorNamesMap[normalizedCategory]?
            return @qualityFactorNamesMap[normalizedCategory]
        
        # Known quality factor ID to readable name mappings
        knownQualityFactors = 
            "commitscontribution": "Commits Contribution"
            "commitstasksrelation": "Commits Tasks Relation"
            "commitsmanagement": "Commits Management"
            "fulfillmentoftasks": "Fulfillment of Tasks"
            "taskscontribution": "Tasks Contribution"
            "taskseffortinformation": "Tasks Effort Information"
            "modifiedlinescontribution": "Modified Lines Contribution"
            "userstoriesdefinitionquality": "User Stories Definition Quality"
            "deviationmetrics": "Deviation Metrics"
            "activitydistribution": "Activity Distribution"
            "unassignedtasks": "Unassigned Tasks"
            "closed_tasks": "Closed Tasks"
            "commits": "Commits"
            "modified_lines": "Modified Lines"
            "tasks": "Tasks"
        
        if knownQualityFactors[normalizedCategory]?
            return knownQualityFactors[normalizedCategory]
        
        # Fallback: Split camelCase and lowercase words, then title case
        # "commitscontribution" -> "Commits Contribution"
        # First try to split by common patterns
        formatted = categoryStr
            # Insert space before uppercase letters (for camelCase)
            .replace(/([a-z])([A-Z])/g, '$1 $2')
            # Split by underscores
            .replace(/_/g, ' ')
            # Split common concatenated words
            .replace(/contribution/gi, ' Contribution')
            .replace(/relation/gi, ' Relation')
            .replace(/management/gi, ' Management')
            .replace(/information/gi, ' Information')
            .replace(/distribution/gi, ' Distribution')
            .replace(/fulfillment/gi, 'Fulfillment ')
            .replace(/deviation/gi, 'Deviation ')
            .replace(/modified/gi, 'Modified ')
            .replace(/quality/gi, ' Quality')
            # Clean up multiple spaces
            .replace(/\s+/g, ' ')
            .trim()
        
        # Title case each word
        words = formatted.split(' ')
        words.map((word) ->
            if word.length > 0
                word.charAt(0).toUpperCase() + word.slice(1).toLowerCase()
            else
                word
        ).join(' ')

    composeTeamHistoricalChart: (collection, metricLabelKey, filteredEntries) ->
        return null unless collection?
        chartData = @.buildChartDatasetFromEntries(collection.student, collection.category, filteredEntries)
        return null unless chartData

        translatedLabel = null
        if metricLabelKey and @translate?.instant?
            translatedLabel = @translate.instant(metricLabelKey)

        baseLabel = @.formatMetricLabel(collection.metricId) or collection.metricName or @.formatMetricCategoryLabel(collection.category)

        metricLabel = translatedLabel or baseLabel

        titleKey = "METRICS.TEAM_HISTORICAL_CARD_TITLE"
        title = if @translate?.instant?
            @translate.instant(titleKey, {metric: metricLabel, user: collection.student})
        else
            "#{metricLabel} · #{collection.student}"

        {
            id: "#{collection.category}::#{collection.student}"
            metric: collection.category
            metricLabel: metricLabelKey or metricLabel
            user: collection.student
            title: title
            chartData: chartData
        }

    composeAggregatedTeamHistoricalCharts: (chartsByCategory, dateFrom, dateTo) ->
        charts = []
        return charts unless chartsByCategory?

        for own categoryId, categoryCollections of chartsByCategory
            chart = @.composeAggregatedTeamHistoricalChart(categoryId, categoryCollections, dateFrom, dateTo)
            charts.push(chart) if chart?

        charts.sort (a, b) ->
            labelA = if a?.metricLabel? then a.metricLabel.toString() else ""
            labelB = if b?.metricLabel? then b.metricLabel.toString() else ""
            labelA.localeCompare(labelB)

        charts

    composeAggregatedTeamHistoricalChart: (categoryId, categoryCollections, dateFrom, dateTo) ->
        return null unless categoryCollections? and typeof categoryCollections is "object"

        try
            @.registerUserColors(Object.keys(categoryCollections))
        catch error
            console.warn("Unable to register colors for aggregated category #{categoryId}:", error)

        datasetInfos = []
        labelSet = {}
        allValues = []

        for own student, collection of categoryCollections
            continue unless collection?.entries? and angular.isArray(collection.entries)

            filteredEntries = @.filterHistoricalEntries(collection.entries, dateFrom, dateTo)
            continue unless angular.isArray(filteredEntries) and filteredEntries.length

            chartData = @.buildChartDatasetFromEntries(collection.student, collection.category, filteredEntries)
            continue unless chartData?

            labels = chartData.labels or []
            dataset = chartData.datasets?[0]
            continue unless angular.isArray(labels) and labels.length and dataset?

            datasetTemplate = angular.copy(dataset) or {}
            valueMap = {}

            for label, idx in labels
                continue unless label?
                value = dataset.data?[idx]
                if typeof value is "number" and !isNaN(value)
                    allValues.push(value)
                    valueMap[label] = value
                else
                    valueMap[label] = null
                labelSet[label] = true

            continue unless Object.keys(valueMap).length

            datasetInfos.push({
                dataset: datasetTemplate
                valueMap: valueMap
                student: collection.student
            })

        labels = Object.keys(labelSet).sort (a, b) ->
            a.localeCompare(b)

        return null unless labels.length and datasetInfos.length

        datasets = []

        for info in datasetInfos
            datasetClone = info.dataset or {}
            datasetClone.data = labels.map (label) ->
                value = info.valueMap[label]
                if typeof value is "number" and !isNaN(value)
                    value
                else if value?
                    numeric = Number(value)
                    if isNaN(numeric)
                        null
                    else
                        numeric
                else
                    null

            datasetClone.fill = false
            datasetClone.label = datasetClone.label or info.student

            hasNumeric = false
            if angular.isArray(datasetClone.data)
                hasNumeric = datasetClone.data.some (value) ->
                    typeof value is "number" and !isNaN(value)

            continue unless hasNumeric

            datasets.push(datasetClone)

        return null unless datasets.length

        axisConfig = @.resolveHistoricalAxisConfig(categoryId, allValues)

        metricLabelKey = @.metricCategoryLabelKey(categoryId)
        translatedLabel = null
        if metricLabelKey and @translate?.instant?
            translatedLabel = @translate.instant(metricLabelKey)

        baseLabel = @.formatMetricCategoryLabel(categoryId)
        metricLabel = translatedLabel or baseLabel

        userLabel = null
        if @translate?.instant?
            userLabel = @translate.instant("METRICS.TEAM_HISTORICAL_ALL_USERS")
        userLabel ?= "All Users"

        titleKey = "METRICS.TEAM_HISTORICAL_CARD_TITLE"
        title = if @translate?.instant?
            @translate.instant(titleKey, {metric: metricLabel, user: userLabel})
        else
            "#{metricLabel} · #{userLabel}"

        chartData =
            title: metricLabel
            labels: labels
            datasets: datasets
            showLegend: datasets.length > 1
            yAxisMax: axisConfig.max
            yAxisStep: axisConfig.step
            isPercentage: axisConfig.isPercentage
            metricCategory: categoryId

        {
            id: "#{categoryId}::all"
            metric: categoryId
            metricLabel: metricLabelKey or metricLabel
            user: userLabel
            title: title
            chartData: chartData
        }

    ###
    # Apply a date preset to the given filters object.
    # Calculates actual from/to dates based on the preset.
    # @param filters {Object} The filters object to modify
    # @param presetId {String} The preset identifier
    ###
    applyDatePreset: (filters, presetId) ->
        return unless filters?
        
        today = new Date()
        toDate = @.formatDateForInput(today)
        fromDate = null
        
        switch presetId
            when "last_7_days"
                fromDate = @.formatDateForInput(new Date(today.getTime() - 7 * 24 * 60 * 60 * 1000))
            when "last_14_days"
                fromDate = @.formatDateForInput(new Date(today.getTime() - 14 * 24 * 60 * 60 * 1000))
            when "last_30_days"
                fromDate = @.formatDateForInput(new Date(today.getTime() - 30 * 24 * 60 * 60 * 1000))
            when "last_90_days"
                fromDate = @.formatDateForInput(new Date(today.getTime() - 90 * 24 * 60 * 60 * 1000))
            when "last_semester"
                fromDate = @.formatDateForInput(new Date(today.getTime() - 180 * 24 * 60 * 60 * 1000))
            when "last_year"
                fromDate = @.formatDateForInput(new Date(today.getTime() - 365 * 24 * 60 * 60 * 1000))
            when "current_month"
                firstOfMonth = new Date(today.getFullYear(), today.getMonth(), 1)
                fromDate = @.formatDateForInput(firstOfMonth)
            when "current_semester"
                # Academic semester: Sep-Jan or Feb-Jul
                month = today.getMonth() + 1  # JS months are 0-indexed
                if month >= 9  # Fall semester (Sep-Jan)
                    fromDate = @.formatDateForInput(new Date(today.getFullYear(), 8, 1))
                else if month >= 2  # Spring semester (Feb-Jul)
                    fromDate = @.formatDateForInput(new Date(today.getFullYear(), 1, 1))
                else  # January (fall semester of previous year)
                    fromDate = @.formatDateForInput(new Date(today.getFullYear() - 1, 8, 1))
            when "all_time"
                fromDate = "2020-01-01"
            else
                # Custom or null - clear preset but keep existing dates
                filters.preset = null
                return
        
        filters.preset = presetId
        filters.dateFrom = fromDate
        filters.dateTo = toDate

    ###
    # Format a Date object to YYYY-MM-DD string for date input
    ###
    formatDateForInput: (date) ->
        return null unless date?
        year = date.getFullYear()
        month = String(date.getMonth() + 1).padStart(2, '0')
        day = String(date.getDate()).padStart(2, '0')
        "#{year}-#{month}-#{day}"

    ###
    # Get human-readable label for the current date range
    ###
    getDateRangeLabel: (filters) ->
        return "" unless filters?
        
        if filters.preset
            presetOption = @scope.metricsView.datePresetOptions?.find (opt) -> opt.id is filters.preset
            if presetOption?.label and @translate?.instant?
                return @translate.instant(presetOption.label)
        
        if filters.dateFrom and filters.dateTo
            return "#{filters.dateFrom} - #{filters.dateTo}"
        else if filters.dateFrom
            return "From #{filters.dateFrom}"
        else if filters.dateTo
            return "Until #{filters.dateTo}"
        
        return ""

    applyTeamHistoricalFilters: ->
        filters = @scope.metricsView.teamHistoricalFilters or {}
        source = @scope.metricsView.teamHistoricalSource

        applyOverrides = (chartsList) =>
            context =
                charts: chartsList
                filters: filters
                source: source
                project: @scope.project
                scope: @scope
            transformedCharts = @metricsHooks.transformTeamHistoricalCharts(context)
            if angular.isArray(transformedCharts)
                return transformedCharts
            if angular.isArray(context?.charts)
                return context.charts
            return chartsList

        unless source? and source.chartsByCategory?
            @scope.metricsView.teamHistoricalCharts = []
            return

        metric = filters.metric or "all"
        user = filters.user or "all"
        dateFrom = filters.dateFrom or null
        dateTo = filters.dateTo or null

        if user is "all" and metric is "all"
            aggregatedCharts = @.composeAggregatedTeamHistoricalCharts(source.chartsByCategory, dateFrom, dateTo)
            @scope.metricsView.teamHistoricalCharts = applyOverrides(aggregatedCharts)
            return

        metricLabelKey = if metric is "all" then null else @.metricCategoryLabelKey(metric)
        charts = []

        processCollection = (collection) =>
            filteredEntries = @.filterHistoricalEntries(collection.entries, dateFrom, dateTo)
            return unless filteredEntries?.length
            chart = @.composeTeamHistoricalChart(collection, metricLabelKey, filteredEntries)
            charts.push(chart) if chart

        if user is "all"
            if metric is "all"
                for own categoryId, categoryCollections of source.chartsByCategory
                    for own student, collection of categoryCollections
                        processCollection(collection)
            else
                chartsByCategory = source.chartsByCategory?[metric] or {}
                for own student, collection of chartsByCategory
                    processCollection(collection)
        else
            if metric is "all"
                userCollections = source.chartsByUser?[user] or {}
                for own categoryId, collection of userCollections
                    processCollection(collection)
            else
                collection = source.chartsByUser?[user]?[metric]
                if collection
                    processCollection(collection)

        charts.sort (a, b) ->
            a.user.localeCompare(b.user)

        @scope.metricsView.teamHistoricalCharts = applyOverrides(charts)

    filterProjectHistoricalPoints: (dataPoints, dateFrom, dateTo) ->
        return [] unless angular.isArray(dataPoints)

        fromTimestamp = @.normalizeFilterDate(dateFrom)
        toTimestamp = @.normalizeFilterDate(dateTo)

        return dataPoints.slice() unless fromTimestamp? or toTimestamp?

        if toTimestamp?
            toTimestamp += 24 * 60 * 60 * 1000 - 1

        dataPoints.filter (point) =>
            timestamp = @.extractHistoricalPointTimestamp(point)
            include = true
            if fromTimestamp? and timestamp?
                include = false if timestamp < fromTimestamp
            if include and toTimestamp? and timestamp?
                include = false if timestamp > toTimestamp
            include

    applyProjectHistoricalFilters: (historicalMetrics = null) ->
        historicalMetrics ?= @scope.metricsView.data?.historicalMetrics

        unless historicalMetrics?
            @scope.metricsView.projectHistoricalCharts = []
            return

        filters = @scope.metricsView.projectHistoricalFilters or {}
        rawProjectMetrics = historicalMetrics?.raw?.projectMetrics or {}
        mergedProjectMetrics = @.mergeHistoricalMetricSeries(rawProjectMetrics)
        filteredData = {}

        applyOverrides = (chartsList, chartMapReference) =>
            context =
                charts: chartsList
                filters: filters
                rawChartMap: chartMapReference
                project: @scope.project
                scope: @scope
            transformedCharts = @metricsHooks.transformProjectHistoricalCharts(context)
            if angular.isArray(transformedCharts)
                return transformedCharts
            if angular.isArray(context?.charts)
                return context.charts
            return chartsList

        for own normalizedId, bundle of mergedProjectMetrics
            dataPoints = bundle?.dataPoints
            continue unless angular.isArray(dataPoints) and dataPoints.length

            filteredPoints = @.filterProjectHistoricalPoints(dataPoints, filters.dateFrom, filters.dateTo)
            continue unless filteredPoints.length
            filteredData[bundle.metricId] = filteredPoints

        chartMap = @.convertRawMetricsToCharts(filteredData, 'project')
        charts = []

        for metricId in @metricsConfig.projectHistoricalMetricsOrder
            chartData = chartMap[metricId]
            continue unless chartData?

            title = chartData.title or @.formatMetricLabel(metricId)
            charts.push({
                id: metricId
                title: title
                chartData: chartData
            })

        for own metricId, chartData of chartMap when @metricsConfig.projectHistoricalMetricsOrder.indexOf(metricId) is -1
            title = chartData.title or @.formatMetricLabel(metricId)
            charts.push({
                id: metricId
                title: title
                chartData: chartData
            })

        @scope.metricsView.projectHistoricalCharts = applyOverrides(charts, chartMap)

    updateTeamHistoricalSource: (historicalMetrics) ->
        unless historicalMetrics?
            @scope.metricsView.teamHistoricalSource = null
            @scope.metricsView.teamHistoricalCharts = []
            @.updateProjectHistoricalCharts(null)
            return

        rawUserMetrics = historicalMetrics?.raw?.userMetrics or {}
        teamData = @.buildTeamHistoricalData(rawUserMetrics)

        @scope.metricsView.teamHistoricalSource = teamData

        if teamData?.users?.length
            @.registerUserColors(teamData.users)
            @.mergeTeamHistoricalUsers(teamData.users)

        @.applyTeamHistoricalFilters()
        @.updateProjectHistoricalCharts(historicalMetrics)

    updateProjectHistoricalCharts: (historicalMetrics) ->
        if historicalMetrics?
            @.applyProjectHistoricalFilters(historicalMetrics)
        else
            @scope.metricsView.projectHistoricalCharts = []

    buildTeamOverviewDefaultState: ->
        {
            usersList: []
            uiUsers: []
            activeUsers: {}
            activeCount: 0
            baseRadar: null
            baseClosedTasks: null
            filteredRadar: null
            filteredClosedTasks: null
            userLabels: {}
            datasetLabelToUser: {}
            barLabelToUser: {}
        }

    resetTeamOverviewState: ->
        @scope.metricsView.teamOverview = @.buildTeamOverviewDefaultState()

    initializeTeamOverviewState: ->
        @.resetTeamOverviewState()

        data = @scope.metricsView.data
        if !data?
            return

        overview = @scope.metricsView.teamOverview
        overview.baseRadar = angular.copy(data.studentsOverallRadar) or null
        overview.baseClosedTasks = angular.copy(data.studentsClosedTasksBar) or null

        usersList = data?.usersMetricsList
        unless angular.isArray(usersList) and usersList.length > 0
            overview.filteredRadar = angular.copy(overview.baseRadar) or null
            overview.filteredClosedTasks = angular.copy(overview.baseClosedTasks) or null
            overview.activeCount = 0
            return

        overview.usersList = usersList.slice()
        overview.uiUsers = []
        overview.userLabels = {}
        overview.datasetLabelToUser = {}
        overview.barLabelToUser = {}
        overview.activeUsers = {}

        for user in usersList when user?
            username = user.username or user.displayName or user.name or user.id
            continue unless username?
            username = username.toString()
            displayName = user.displayName or user.name or username
            overview.userLabels[username] = displayName
            overview.activeUsers[username] = true

            colorPalette = @.resolveUserColor(user)
            primaryColor = colorPalette?.solid or colorPalette?.fill or "rgba(79, 70, 229, 0.85)"
            borderColor = colorPalette?.border or "#312e81"

            overview.uiUsers.push({
                username: username
                displayName: displayName
                color: primaryColor
                borderColor: borderColor
            })

        if overview.baseRadar?.datasets
            for dataset in overview.baseRadar.datasets when dataset?.label?
                label = dataset.label
                matchedUsername = @.matchUserByLabel(label, overview)
                overview.datasetLabelToUser[label] = matchedUsername if matchedUsername?

        if angular.isArray(overview.baseClosedTasks?.labels)
            for label in overview.baseClosedTasks.labels when label?
                matchedUsername = @.matchUserByLabel(label, overview)
                overview.barLabelToUser[label] = matchedUsername if matchedUsername?

        overview.activeCount = overview.uiUsers.length
        @.updateTeamOverviewCharts()

    updateTeamOverviewCharts: ->
        overview = @scope.metricsView.teamOverview
        return unless overview?

        usersList = overview.usersList or []
        unless angular.isArray(usersList) and usersList.length > 0
            overview.activeCount = 0
            overview.filteredRadar = angular.copy(overview.baseRadar) or null
            overview.filteredClosedTasks = angular.copy(overview.baseClosedTasks) or null
            return

        activeUsernames = []
        for user in usersList when user?
            username = user.username or user.displayName or user.id
            continue unless username?
            username = username.toString()
            isActive = !!overview.activeUsers?[username]
            activeUsernames.push(username) if isActive

        if activeUsernames.length is 0
            for user in usersList when user?.username?
                username = user.username.toString()
                overview.activeUsers[username] = true
                activeUsernames.push(username)

        overview.activeCount = activeUsernames.length

        activeLabels = {}
        for username in activeUsernames
            label = overview.userLabels?[username] or username
            activeLabels[label] = true

        if overview.baseRadar?
            filteredRadar = angular.copy(overview.baseRadar) or {}
            datasets = []
            for dataset in overview.baseRadar?.datasets or []
                label = dataset?.label
                include = false
                if label?
                    username = overview.datasetLabelToUser?[label] or @.matchUserByLabel(label, overview)
                    if username?
                        include = !!overview.activeUsers[username]
                    else
                        include = !!activeLabels[label]
                include = true unless label?
                datasets.push(angular.copy(dataset)) if include
            if datasets.length is 0
                overview.filteredRadar = angular.copy(overview.baseRadar) or null
            else
                filteredRadar.datasets = datasets
                overview.filteredRadar = filteredRadar
        else
            overview.filteredRadar = null

        if overview.baseClosedTasks?
            baseBar = overview.baseClosedTasks
            filteredLabels = []
            selectedIndices = []

            for label, idx in baseBar.labels or []
                include = false
                if label?
                    username = overview.barLabelToUser?[label] or @.matchUserByLabel(label, overview)
                    if username?
                        include = !!overview.activeUsers[username]
                    else
                        include = !!activeLabels[label]
                include = true unless label?
                if include
                    filteredLabels.push(label)
                    selectedIndices.push(idx)

            if filteredLabels.length is 0
                overview.filteredClosedTasks = angular.copy(baseBar) or null
            else
                filteredBar = angular.copy(baseBar) or {}
                filteredBar.labels = filteredLabels
                filteredDatasets = []

                for dataset in baseBar.datasets or []
                    cloned = angular.copy(dataset) or {}
                    if angular.isArray(dataset?.data)
                        cloned.data = selectedIndices.map (index) -> dataset.data[index]
                    if angular.isArray(dataset?.backgroundColor)
                        cloned.backgroundColor = selectedIndices.map (index) -> dataset.backgroundColor[index]
                    if angular.isArray(dataset?.borderColor)
                        cloned.borderColor = selectedIndices.map (index) -> dataset.borderColor[index]
                    if angular.isArray(dataset?.hoverBackgroundColor)
                        cloned.hoverBackgroundColor = selectedIndices.map (index) -> dataset.hoverBackgroundColor[index]
                    filteredDatasets.push(cloned)

                filteredBar.datasets = filteredDatasets
                overview.filteredClosedTasks = filteredBar
        else
            overview.filteredClosedTasks = null

    toggleTeamOverviewUser: (username) ->
        return unless username?

        overview = @scope.metricsView.teamOverview
        return unless overview?.activeUsers?

        normalized = username.toString()
        isActive = !!overview.activeUsers[normalized]

        if isActive and overview.activeCount <= 1
            return

        overview.activeUsers[normalized] = !isActive
        @.updateTeamOverviewCharts()

    resetTeamOverviewUsers: ->
        overview = @scope.metricsView.teamOverview
        return unless overview?

        for user in overview.usersList or []
            username = user?.username or user?.displayName or user?.id
            continue unless username?
            overview.activeUsers[username.toString()] = true

        @.updateTeamOverviewCharts()

    matchUserByLabel: (label, overview = null) ->
        return null unless label?

        labelStr = label.toString()
        return null unless labelStr.length

        overview ?= @scope.metricsView.teamOverview
        return null unless overview?

        username = overview.datasetLabelToUser?[labelStr] or overview.barLabelToUser?[labelStr]
        return username if username?

        for user in overview.uiUsers or [] when user?
            if user.displayName is labelStr or user.username is labelStr
                return user.username

        null

    initializeTeamHistoricalUsers: (usersList) ->
        baseOption = {id: "all", label: "METRICS.TEAM_HISTORICAL_ALL_USERS", translate: true}
        options = [baseOption]
        selectedUser = @scope.metricsView.teamHistoricalFilters?.user

        @.registerUserColors(usersList)

        if angular.isArray(usersList)
            seen = {}
            for user in usersList when user?
                username = user.username or user.displayName or user.name or user.id
                continue unless username? and username.toString().trim().length
                normalized = username.toString().trim()
                continue if seen[normalized]
                seen[normalized] = true
                displayName = user.displayName or user.name or normalized
                options.push({id: normalized, label: displayName, translate: false})

        hasSelected = false
        if selectedUser?
            hasSelected = options.some (opt) -> opt.id is selectedUser

        @scope.metricsView.teamHistoricalUserOptions = options

        unless hasSelected
            @scope.metricsView.teamHistoricalFilters.user = "all"

    mergeTeamHistoricalUsers: (usernames) ->
        return unless angular.isArray(usernames)

        @.registerUserColors(usernames)

        existing = @scope.metricsView.teamHistoricalUserOptions or []
        options = []
        seen = {}

        for option in existing when option?
            seen[option.id] = true
            options.push(option)

        for username in usernames when username?
            normalized = username.toString().trim()
            continue unless normalized.length
            continue if seen[normalized]
            seen[normalized] = true
            options.push({id: normalized, label: normalized, translate: false})

        options.sort (a, b) ->
            if a.id is "all"
                return -1
            if b.id is "all"
                return 1
            a.label.toString().localeCompare(b.label.toString())

        selectedUser = @scope.metricsView.teamHistoricalFilters?.user
        hasSelected = false
        if selectedUser?
            hasSelected = options.some (opt) -> opt.id is selectedUser

        @scope.metricsView.teamHistoricalUserOptions = options

        unless hasSelected
            @scope.metricsView.teamHistoricalFilters.user = "all"
    
    formatMetricLabel: (metricId) ->
        """
        Convert metric ID to a readable label
        Example: acceptance_criteria_check -> Acceptance Criteria Application
        """
        return metricId unless metricId

        # Known metric ID to label mappings
        labelMap = {
            'acceptance_criteria_check': 'Acceptance Criteria Application'
            'closed_tasks_with_ae': 'Closed Tasks with Actual Effort Information'
            'commits_anonymous': 'Anonymous Commits'
            'commits_sd': 'Commits Standard Deviation'
            'commits_taskreference': 'Commits Tasks Relation'
            'deviation_effort_estimation_simple': 'Deviation in Estimation of Task Effort'
            'learn_hours': 'Learning hours'
            'pattern_check': 'Use of User Story pattern'
            'tasks_sd': 'Tasks Standard Deviation'
            'tasks_with_ee': 'Tasks with Estimated Effort Information'
            'unassignedtasks': 'Unassigned tasks'
        }

        if labelMap[metricId]
            return labelMap[metricId]

        # Handle user-scoped metrics like "closedtasks_username"
        if metricId.indexOf('_') isnt -1
            parts = metricId.split('_')
            prefix = parts[0]
            userMetricMap = {
                'closedtasks': 'Closed Tasks'
                'completedtasks': 'Closed Tasks'
                'assignedtasks': 'Tasks'
                'tasksratio': 'Tasks'
                'commits': 'Commits'
                'modifiedlines': 'Modified Lines'
                'completedus': 'Completed User Stories'
                'totalus': 'Total User Stories'
            }

            if userMetricMap[prefix]?
                return userMetricMap[prefix]

        # Fallback: Convert snake_case to Title Case
        words = metricId.split('_')
        return words.map((word) ->
            if word.length > 0
                word.charAt(0).toUpperCase() + word.slice(1)
            else
                word
        ).join(' ')

# Pol Alcoverro added - Filter to check if object has data
module.filter("hasData", -> 
    (obj) ->
        return false unless obj?
        return false unless typeof obj is 'object'
        return Object.keys(obj).length > 0
)

# Pol Alcoverro added - Register controller
module.controller("MetricsController", MetricsController)
