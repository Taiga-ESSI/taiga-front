###
# Sergio Utrilla added - Instructor Dashboard controllers
# Descripción: Controladores para el dashboard del instructor. InstructorHomeController muestra
#              la lista de subjects y editions; InstructorEditionController muestra el dashboard
#              de una edition concreta con métricas agregadas por equipo.
###

taiga = @.taiga
mixOf = @.taiga.mixOf

module = angular.module("taigaInstructor")


# Returns the same traffic-light palette used by the metrics view (getInternalGaugePalette).
# Mirrors the logic in metrics/main.coffee so instructor speedometers match student speedometers.
_getMetricPalette = (metricId) ->
    id = (metricId or '').toString().toLowerCase()

    isAssigned = id.indexOf('assignedtasks') isnt -1 or
                 id.indexOf('totalus') isnt -1 or
                 id.indexOf('assignedus') isnt -1

    if isAssigned
        return [
            { value: 10, color: 'rgba(251, 191, 36, 0.9)' }
            { value: 20, color: 'rgba(34, 197, 94, 0.9)' }
            { value: 20, color: 'rgba(251, 191, 36, 0.9)' }
            { value: 50, color: 'rgba(239, 68, 68, 0.9)' }
        ]

    isWorsening = /unassigned|deviation|commits_anonymous|pattern_check/.test(id)

    if isWorsening
        return [
            { value: 33, color: 'rgba(34, 197, 94, 0.9)' }
            { value: 33, color: 'rgba(251, 191, 36, 0.9)' }
            { value: 34, color: 'rgba(239, 68, 68, 0.9)' }
        ]

    # Default: higher is better (Red → Yellow → Green)
    return [
        { value: 33, color: 'rgba(239, 68, 68, 0.9)' }
        { value: 33, color: 'rgba(251, 191, 36, 0.9)' }
        { value: 34, color: 'rgba(34, 197, 94, 0.9)' }
    ]


_buildCategoryPalettes = (categoriesData) ->
    grouped = {}
    return grouped unless categoriesData? and angular.isArray(categoriesData)
    for entry in categoriesData when entry?
        nameKey = (entry.name or entry.category or entry.displayName or '').toString().trim().toLowerCase()
        continue unless nameKey
        upper = parseFloat(entry.upperThreshold)
        grouped[nameKey] ?= []
        grouped[nameKey].push({
            color: entry.color or entry.hex or '#2563EB'
            upperThreshold: if isFinite(upper) then Math.max(0, upper) else null
        })
    for nameKey, palette of grouped
        valid = palette.filter (item) -> item.upperThreshold? and isFinite(item.upperThreshold)
        grouped[nameKey] = if valid.length > 0 \
            then valid.sort((a, b) -> a.upperThreshold - b.upperThreshold) \
            else palette.slice()
    grouped

_resolveCategoryColor = (palettes, categoryKey, value) ->
    return null unless categoryKey?
    key = categoryKey.toString().trim().toLowerCase()
    palette = palettes?[key]
    return null unless palette? and palette.length
    ratio = Math.max(0, parseFloat(value) or 0)
    matchedColor = null
    for item in palette when item?.upperThreshold? and isFinite(item.upperThreshold)
        if ratio <= item.upperThreshold + 1e-9
            matchedColor = item.color
            break
    matchedColor or palette[palette.length - 1]?.color or null

_buildCategorySegments = (palettes, categoryKey) ->
    return null unless categoryKey?
    key = categoryKey.toString().trim().toLowerCase()
    palette = palettes?[key]
    return null unless palette? and palette.length
    segments = []
    lastThreshold = 0
    for entry in palette when entry?
        upper = Number(entry.upperThreshold)
        continue unless isFinite(upper)
        clamped = Math.max(lastThreshold, Math.min(Math.max(upper, 0), 1))
        segmentRatio = clamped - lastThreshold
        continue unless segmentRatio > 0
        segments.push({ color: entry.color or '#2563EB', value: segmentRatio, upperThreshold: clamped })
        lastThreshold = clamped
    if lastThreshold < 1
        remainderRatio = 1 - lastThreshold
        if remainderRatio > 0
            fallbackColor = palette[palette.length - 1]?.color or '#CBD5F5'
            segments.push({ color: fallbackColor, value: remainderRatio, upperThreshold: 1 })
    if segments.length then segments else null

_enrichMetricsWithPalette = (groups) ->
    (groups or []).map (group) ->
        enriched = angular.extend({}, group)
        isExternal = group.metrics_provider is 'external'
        palettes = if isExternal then _buildCategoryPalettes(group.metrics_categories or []) else {}
        enriched.metrics = (group.metrics or []).map (m) ->
            if isExternal
                # Mirror the student view: use categoryName first, then first qualityFactor as fallback.
                categoryKey = m.categoryName or (m.qualityFactors or [])[0] or m.id
                categoryColor = _resolveCategoryColor(palettes, categoryKey, m.value)
                categorySegments = _buildCategorySegments(palettes, categoryKey)
                angular.extend({}, m, {
                    palette: categorySegments
                    color: categoryColor or 'rgb(37, 99, 235)'
                })
            else
                angular.extend({}, m, { palette: _getMetricPalette(m.id), color: null })
        enriched


class InstructorHomeController extends mixOf(taiga.Controller, taiga.PageMixin)
    @.$inject = [
        "$scope"
        "$q"
        "$tgHttp"
        "$tgUrls"
        "tgAppMetaService"
        "$translate"
    ]

    constructor: (@scope, @q, @http, @urls, @appMetaService, @translate) ->
        @translate("INSTRUCTOR.SECTION_NAME").then (name) =>
            @appMetaService.setAll(name, "")

        @scope.view =
            loading: true
            error: null
            subjects: []
            statusFilter: 'all'

        @scope.setStatusFilter = (f) => @scope.view.statusFilter = f
        @scope.getFilteredEditions = (subject) => @.getFilteredEditions(subject)

        @.load()

    load: ->
        @scope.view.loading = true
        @scope.view.error = null

        subjectsReq = @http.get(@urls.resolve("academics-subjects")).then (r) -> r.data
        editionsReq = @http.get(@urls.resolve("academics-editions")).then (r) -> r.data

        @q.all([subjectsReq, editionsReq]).then ([subjects, editions]) =>
            editionsBySubject = _.groupBy(editions, (e) -> e.subject?.id)
            @scope.view.subjects = subjects.map (s) ->
                s.editions = editionsBySubject[s.id] or []
                s
            @scope.view.loading = false
        .catch (err) =>
            status = err.status or err.statusCode
            if status == 403
                @scope.view.error = "INSTRUCTOR.ACCESS_DENIED"
            else
                @scope.view.error = "INSTRUCTOR.LOAD_ERROR"
            @scope.view.loading = false

    getFilteredEditions: (subject) ->
        STATUS_ORDER = { ACTIVE: 0, PLANNED: 1, CLOSED: 2 }
        TERM_ORDER   = { Q2: 0, Q1: 1, ANNUAL: 2 }
        filter = @scope.view.statusFilter
        editions = if filter == 'all' then subject.editions else subject.editions.filter (e) -> e.status == filter
        editions.slice().sort (a, b) ->
            sa = if STATUS_ORDER[a.status]? then STATUS_ORDER[a.status] else 99
            sb = if STATUS_ORDER[b.status]? then STATUS_ORDER[b.status] else 99
            if sa != sb then return sa - sb
            if a.academic_year > b.academic_year then return -1
            if a.academic_year < b.academic_year then return 1
            ta = if TERM_ORDER[a.term]? then TERM_ORDER[a.term] else 99
            tb = if TERM_ORDER[b.term]? then TERM_ORDER[b.term] else 99
            ta - tb

module.controller("InstructorHomeController", InstructorHomeController)


class InstructorEditionController extends mixOf(taiga.Controller, taiga.PageMixin)
    @.$inject = [
        "$scope"
        "$routeParams"
        "$tgHttp"
        "$tgUrls"
        "tgAppMetaService"
        "$translate"
        "$timeout"
    ]

    constructor: (@scope, @params, @http, @urls, @appMetaService, @translate, @timeout) ->
        @scope.editionKey = @params.editionKey

        @scope.view =
            loading: true
            error: null
            edition: null
            groups: []
            aggregated: {}
            filteredAggregated: {}
            filteredCharts: {}
            allChartsList: []
            filteredChartsList: []
            chartVersion: 0
            canEditSettings: false
            refreshing: false
            isCoordinator: false
            isProfessor: false
            showViewToggle: false
            professorView: false
            comparisonGroupIds: null    # null = all groups selected
            comparisonMetricIds: null   # null = all metrics selected

        @scope.refresh = => @.refresh()
        @scope.switchToProfessorView = => @.switchView(true)
        @scope.switchToCoordinatorView = => @.switchView(false)
        @scope.toggleGroupInComparison = (groupId) => @.toggleGroupInComparison(groupId)
        @scope.isGroupInComparison = (groupId) => @.isGroupInComparison(groupId)
        @scope.getSelectedGroupCount = => @.getSelectedGroupCount()
        @scope.toggleMetricInComparison = (metricId) => @.toggleMetricInComparison(metricId)
        @scope.isMetricInComparison = (metricId) => @.isMetricInComparison(metricId)
        @scope.getSelectedMetricCount = => @.getSelectedMetricCount()

        @.load(false, true)

    GROUP_COLORS: [
        '#2563EB', '#16A34A', '#DC2626', '#D97706',
        '#7C3AED', '#0891B2', '#DB2777', '#65A30D'
    ]

    load: (force=false, professorView=false) ->
        @scope.view.loading = true
        @scope.view.error = null

        url = @urls.resolve("academics-edition-dashboard", @scope.editionKey)
        params = {}
        if force then params.refresh = "1"
        if professorView then params.professor_view = "1"

        return @http.get(url, params).then (response) =>
            data = response.data
            @scope.view.edition =
                id:  data.course_edition_id
                key: data.course_edition_key
            @scope.view.groups          = _enrichMetricsWithPalette(data.groups)
            @scope.view.aggregated      = data.aggregated or {}
            @scope.view.canEditSettings = data.can_edit_settings is true
            @scope.view.isCoordinator   = data.is_coordinator is true
            @scope.view.isProfessor     = data.is_professor is true
            @scope.view.showViewToggle  = data.is_coordinator is true and data.is_professor is true
            @scope.view.professorView   = professorView
            @scope.view.loading         = false

            # Reset comparison filters when data reloads
            @scope.view.comparisonGroupIds = null
            @scope.view.comparisonMetricIds = null
            @.updateFilteredCharts()

            @translate("INSTRUCTOR.EDITION_TITLE", {key: data.course_edition_key}).then (title) =>
                @appMetaService.setAll(title, "")
        .catch (err) =>
            status = err.status or err.statusCode
            if status == 403
                @scope.view.error = "INSTRUCTOR.ACCESS_DENIED"
            else if status == 404
                @scope.view.error = "INSTRUCTOR.EDITION_NOT_FOUND"
            else
                @scope.view.error = "INSTRUCTOR.LOAD_ERROR"
            @scope.view.loading = false

    buildBarCharts: (aggregated, selectedCodes) ->
        charts = {}
        for metricId, data of aggregated
            continue unless data and data.values and data.values.length > 0
            allLabels = data.values.map (v) -> v.group_code
            allValues = data.values.map (v) -> Math.round((v.value or 0) * 10000) / 100
            allColors = allLabels.map (_, i) => @.GROUP_COLORS[i % @.GROUP_COLORS.length]

            if selectedCodes
                labels = []
                values = []
                colors = []
                for i in [0...allLabels.length]
                    if selectedCodes.indexOf(allLabels[i]) >= 0
                        labels.push(allLabels[i])
                        values.push(allValues[i])
                        colors.push(allColors[i])
            else
                labels = allLabels
                values = allValues
                colors = allColors

            charts[metricId] =
                labels: labels
                datasets: [{
                    label: data.metric_name
                    data: values
                    backgroundColor: colors
                    borderColor: colors
                    borderWidth: 1
                }]
        charts

    updateFilteredCharts: ->
        rawAggregated = @scope.view.aggregated
        aggData = {}
        selectedCodes = null

        if @scope.view.comparisonGroupIds is null
            for metricId, data of rawAggregated
                continue unless data and data.values and data.values.length > 0
                nums = data.values.map (v) -> v.value
                aggData[metricId] = angular.extend({}, data,
                    avg: Math.round(_.sum(nums) / nums.length * 10000) / 100
                    min: Math.round(_.min(nums) * 10000) / 100
                    max: Math.round(_.max(nums) * 10000) / 100
                )
        else
            selectedIds = @scope.view.comparisonGroupIds
            selectedGroups = @scope.view.groups.filter (g) -> selectedIds.indexOf(g.group_id) >= 0
            selectedCodes = selectedGroups.map (g) -> g.group_code

            for metricId, data of rawAggregated
                continue unless data and data.values
                filteredValues = data.values.filter (v) -> selectedCodes.indexOf(v.group_code) >= 0
                if filteredValues.length > 0
                    nums = filteredValues.map (v) -> v.value
                    aggData[metricId] = angular.extend({}, data,
                        values: filteredValues
                        avg: Math.round(_.sum(nums) / nums.length * 10000) / 100
                        min: Math.round(_.min(nums) * 10000) / 100
                        max: Math.round(_.max(nums) * 10000) / 100
                    )

        chartsData = @.buildBarCharts(rawAggregated, selectedCodes)

        allChartsList = Object.keys(chartsData).map (metricId) =>
            agg = aggData[metricId] or {}
            {
                metric_id: metricId
                metric_name: agg.metric_name or metricId
                avg: agg.avg or 0
                min: agg.min or 0
                max: agg.max or 0
                chartData: chartsData[metricId]
            }

        selectedMetricIds = @scope.view.comparisonMetricIds
        filteredChartsList = if selectedMetricIds?
            allChartsList.filter (item) -> selectedMetricIds.indexOf(item.metric_id) >= 0
        else
            allChartsList

        @scope.view.filteredAggregated = aggData
        @scope.view.filteredCharts = chartsData
        @scope.view.allChartsList = allChartsList
        @scope.view.filteredChartsList = filteredChartsList
        @scope.view.chartVersion += 1

    toggleGroupInComparison: (groupId) ->
        if @scope.view.comparisonGroupIds is null
            allIds = @scope.view.groups.map (g) -> g.group_id
            newIds = allIds.filter (id) -> id != groupId
            return if newIds.length == 0   # must keep at least 1
            @scope.view.comparisonGroupIds = newIds
        else
            idx = @scope.view.comparisonGroupIds.indexOf(groupId)
            if idx >= 0
                return if @scope.view.comparisonGroupIds.length <= 1   # must keep at least 1
                @scope.view.comparisonGroupIds.splice(idx, 1)
            else
                @scope.view.comparisonGroupIds.push(groupId)
            if @scope.view.comparisonGroupIds.length == @scope.view.groups.length
                @scope.view.comparisonGroupIds = null
        @.updateFilteredCharts()

    isGroupInComparison: (groupId) ->
        @scope.view.comparisonGroupIds is null or
        @scope.view.comparisonGroupIds.indexOf(groupId) >= 0

    getSelectedGroupCount: ->
        if @scope.view.comparisonGroupIds is null
            return @scope.view.groups.length
        return @scope.view.comparisonGroupIds.length

    toggleMetricInComparison: (metricId) ->
        if @scope.view.comparisonMetricIds is null
            allIds = @scope.view.allChartsList.map (m) -> m.metric_id
            newIds = allIds.filter (id) -> id != metricId
            return if newIds.length == 0
            @scope.view.comparisonMetricIds = newIds
        else
            idx = @scope.view.comparisonMetricIds.indexOf(metricId)
            if idx >= 0
                return if @scope.view.comparisonMetricIds.length <= 1
                @scope.view.comparisonMetricIds.splice(idx, 1)
            else
                @scope.view.comparisonMetricIds.push(metricId)
            if @scope.view.comparisonMetricIds.length == @scope.view.allChartsList.length
                @scope.view.comparisonMetricIds = null
        @.updateFilteredCharts()

    isMetricInComparison: (metricId) ->
        @scope.view.comparisonMetricIds is null or
        @scope.view.comparisonMetricIds.indexOf(metricId) >= 0

    getSelectedMetricCount: ->
        if @scope.view.comparisonMetricIds is null
            return @scope.view.allChartsList.length
        return @scope.view.comparisonMetricIds.length

    switchView: (professorView) ->
        if professorView == @scope.view.professorView then return
        @.load(false, professorView)

    refresh: ->
        @scope.view.refreshing = true
        @.load(true, @scope.view.professorView).finally =>
            @scope.view.refreshing = false

module.controller("InstructorEditionController", InstructorEditionController)


class InstructorGroupController extends mixOf(taiga.Controller, taiga.PageMixin)
    @.$inject = [
        "$scope"
        "$routeParams"
        "$tgHttp"
        "$tgUrls"
        "tgAppMetaService"
        "$translate"
    ]

    constructor: (@scope, @params, @http, @urls, @appMetaService, @translate) ->
        @scope.editionKey = @params.editionKey
        @scope.groupCode  = @params.groupCode

        @scope.view =
            loading: true
            error: null
            edition: null
            group: null
            projectMetrics: []
            drilldownAllowed: true
            students: []
            hasStudents: false
            refreshing: false
            studentViewMode: 'table'

        @scope.refresh = => @.refresh()
        @scope.setStudentViewMode = (mode) => @scope.view.studentViewMode = mode

        @.load()

    load: (force=false) ->
        @scope.view.loading = true
        @scope.view.error = null

        url    = @urls.resolve("academics-edition-dashboard", @scope.editionKey)
        params = if force then {refresh: "1"} else {}

        return @http.get(url, params).then (response) =>
            data  = response.data
            rawGroup = _.find(data.groups or [], (g) => g.group_code == @scope.groupCode)

            unless rawGroup
                @scope.view.error   = "INSTRUCTOR.GROUP_NOT_FOUND"
                @scope.view.loading = false
                return

            group = _enrichMetricsWithPalette([rawGroup])[0]

            @scope.view.edition =
                id:  data.course_edition_id
                key: data.course_edition_key

            @scope.view.group             = group
            @scope.view.projectMetrics    = (group.metrics or []).filter (m) -> m.classification == 'project'
            @scope.view.drilldownAllowed  = rawGroup.drilldown_allowed isnt false
            isExternalGroup = rawGroup.metrics_provider is 'external'
            groupPalettes = if isExternalGroup then _buildCategoryPalettes(rawGroup.metrics_categories or []) else {}
            @scope.view.students          = (group.students or []).map (student) ->
                enriched = angular.extend({}, student)
                enriched.metrics = (student.metrics or []).map (m) ->
                    if isExternalGroup
                        categoryKey = m.categoryName or (m.qualityFactors or [])[0] or m.id
                        categoryColor = _resolveCategoryColor(groupPalettes, categoryKey, m.value)
                        categorySegments = _buildCategorySegments(groupPalettes, categoryKey)
                        angular.extend({}, m, {
                            palette: categorySegments
                            color: categoryColor or 'rgb(37, 99, 235)'
                        })
                    else
                        angular.extend({}, m, { palette: _getMetricPalette(m.id), color: null })
                enriched
            @scope.view.hasStudents       = @scope.view.students.length > 0
            @scope.view.loading           = false

            title = "#{group.group_code} · #{data.course_edition_key}"
            @appMetaService.setAll(title, "")
        .catch (err) =>
            status = err.status or err.statusCode
            if status == 403
                @scope.view.error = "INSTRUCTOR.ACCESS_DENIED"
            else if status == 404
                @scope.view.error = "INSTRUCTOR.EDITION_NOT_FOUND"
            else
                @scope.view.error = "INSTRUCTOR.LOAD_ERROR"
            @scope.view.loading = false

    refresh: ->
        @scope.view.refreshing = true
        @.load(true).finally =>
            @scope.view.refreshing = false

module.controller("InstructorGroupController", InstructorGroupController)


class InstructorEditionSettingsController extends mixOf(taiga.Controller, taiga.PageMixin)
    @.$inject = [
        "$scope"
        "$routeParams"
        "$q"
        "$tgHttp"
        "$tgUrls"
        "tgAppMetaService"
        "$translate"
    ]

    constructor: (@scope, @params, @q, @http, @urls, @appMetaService, @translate) ->
        @scope.editionKey = @params.editionKey

        @scope.view =
            loading: true
            error: null
            edition: null
            policyId: null
            projectMetrics: []
            teamMetrics: []
            allowStudentDrilldown: true
            saving: false
            saved: false
            saveError: null

        @scope.save       = => @.save()
        @scope.toggle     = (metric, field) => metric[field] = !metric[field]
        @scope.moveMetric = (list, index, direction) => @.moveMetric(list, index, direction)

        @.load()

    load: ->
        @scope.view.loading = true
        @scope.view.error   = null

        dashboardReq = @http.get(
            @urls.resolve("academics-edition-dashboard", @scope.editionKey),
            {raw: "1"}
        ).then (r) -> r.data

        policyReq = @http.get(
            @urls.resolve("academics-metrics-policies"),
            {course_edition_key: @scope.editionKey}
        ).then (r) -> r.data

        @q.all([dashboardReq, policyReq]).then ([dashboard, policies]) =>
            @scope.view.edition =
                id:  dashboard.course_edition_id
                key: dashboard.course_edition_key

            policy   = policies[0] or {}
            hiddenIds          = policy.hidden_metric_ids or []
            visibleStudentIds  = policy.visible_to_students_metric_ids or []
            projectOrder       = policy.project_metric_order or []
            teamOrder          = policy.team_metric_order or []

            @scope.view.policyId = policy.id or null

            allMetrics = {}
            for group in (dashboard.groups or [])
                for metric in (group.metrics or [])
                    metricId = metric.id.toString()
                    metricName = metric.name or metricId
                    # Team metrics are per-user (e.g. "assignedtasks_sergio.utrilla").
                    # Strip the username suffix so settings show one entry per metric type
                    # and the policy stores base IDs that match all students via prefix check.
                    if metric.classification == 'team'
                        metricId = metricId.split('_')[0]
                        metricName = metricName.replace(/\s*·\s*.+$/, '').trim()
                    _vis = if hiddenIds.indexOf(metricId) >= 0 then 'hidden' else if visibleStudentIds.indexOf(metricId) >= 0 then 'professors_and_students' else 'professors_only'
                    allMetrics[metricId] ?=
                        id:             metricId
                        name:           metricName
                        classification: metric.classification
                        visibility:     _vis

            metrics = _.values(allMetrics)
            projectMetrics = metrics.filter (m) -> m.classification == 'project'
            teamMetrics    = metrics.filter (m) -> m.classification == 'team'

            # Apply saved order from policy
            if projectOrder.length > 0
                projectMetrics.sort (a, b) ->
                    ia = projectOrder.indexOf(a.id)
                    ib = projectOrder.indexOf(b.id)
                    if ia == -1 then ia = projectOrder.length
                    if ib == -1 then ib = projectOrder.length
                    ia - ib

            if teamOrder.length > 0
                teamMetrics.sort (a, b) ->
                    ia = teamOrder.indexOf(a.id)
                    ib = teamOrder.indexOf(b.id)
                    if ia == -1 then ia = teamOrder.length
                    if ib == -1 then ib = teamOrder.length
                    ia - ib

            @scope.view.projectMetrics = projectMetrics
            @scope.view.teamMetrics    = teamMetrics
            @scope.view.loading        = false

            @translate("INSTRUCTOR.SETTINGS_TITLE").then (title) =>
                @appMetaService.setAll(title, "")
        .catch (err) =>
            status = err.status or err.statusCode
            if status == 403
                @scope.view.error = "INSTRUCTOR.ACCESS_DENIED"
            else
                @scope.view.error = "INSTRUCTOR.LOAD_ERROR"
            @scope.view.loading = false

    moveMetric: (list, index, direction) ->
        newIndex = index + direction
        if newIndex < 0 or newIndex >= list.length then return
        item = list.splice(index, 1)[0]
        list.splice(newIndex, 0, item)

    save: ->
        @scope.view.saving    = true
        @scope.view.saved     = false
        @scope.view.saveError = null

        allMetrics = @scope.view.projectMetrics.concat(@scope.view.teamMetrics)

        payload =
            hidden_metric_ids:              allMetrics.filter((m) -> m.visibility == 'hidden').map (m) -> m.id
            visible_to_students_metric_ids: allMetrics.filter((m) -> m.visibility == 'professors_and_students').map (m) -> m.id
            project_metric_order:           @scope.view.projectMetrics.map (m) -> m.id
            team_metric_order:              @scope.view.teamMetrics.map (m) -> m.id

        req =
            if @scope.view.policyId
                payload.course_edition_id = @scope.view.edition.id
                @http.patch(
                    @urls.resolve("academics-metrics-policy-detail", @scope.view.policyId),
                    payload
                )
            else
                payload.course_edition_id = @scope.view.edition.id
                @http.post(@urls.resolve("academics-metrics-policies"), payload)

        req.then (r) =>
            @scope.view.policyId = r.data.id
            @scope.view.saving   = false
            @scope.view.saved    = true
        .catch (err) =>
            status = err.status or err.statusCode
            if status == 403
                @scope.view.saveError = "INSTRUCTOR.ACCESS_DENIED"
            else
                @scope.view.saveError = "INSTRUCTOR.SAVE_ERROR"
            @scope.view.saving = false

module.controller("InstructorEditionSettingsController", InstructorEditionSettingsController)
