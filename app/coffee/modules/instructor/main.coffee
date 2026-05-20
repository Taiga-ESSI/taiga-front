###
# Sergio Utrilla added - Instructor Dashboard controllers
# Descripción: Controladores para el dashboard del instructor. InstructorHomeController muestra
#              la lista de subjects y editions; InstructorEditionController muestra el dashboard
#              de una edition concreta con métricas agregadas por grupo.
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


_enrichMetricsWithPalette = (groups) ->
    (groups or []).map (group) ->
        enriched = angular.extend({}, group)
        enriched.metrics = (group.metrics or []).map (m) ->
            angular.extend({}, m, { palette: _getMetricPalette(m.id) })
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

module.controller("InstructorHomeController", InstructorHomeController)


class InstructorEditionController extends mixOf(taiga.Controller, taiga.PageMixin)
    @.$inject = [
        "$scope"
        "$routeParams"
        "$tgHttp"
        "$tgUrls"
        "tgAppMetaService"
        "$translate"
    ]

    constructor: (@scope, @params, @http, @urls, @appMetaService, @translate) ->
        @scope.editionId = parseInt(@params.editionId, 10)

        @scope.view =
            loading: true
            error: null
            edition: null
            groups: []
            aggregated: {}
            canEditSettings: false
            refreshing: false

        @scope.refresh = => @.refresh()

        @.load()

    GROUP_COLORS: [
        '#2563EB', '#16A34A', '#DC2626', '#D97706',
        '#7C3AED', '#0891B2', '#DB2777', '#65A30D'
    ]

    load: (force=false) ->
        @scope.view.loading = true
        @scope.view.error = null

        url = @urls.resolve("academics-edition-dashboard", @scope.editionId)
        params = if force then {refresh: "1"} else {}

        return @http.get(url, params).then (response) =>
            data = response.data
            @scope.view.edition =
                id:  data.course_edition_id
                key: data.course_edition_key
            @scope.view.groups          = _enrichMetricsWithPalette(data.groups)
            @scope.view.aggregated      = data.aggregated or {}
            @scope.view.charts          = @.buildBarCharts(data.aggregated or {})
            @scope.view.canEditSettings = data.can_edit_settings is true
            @scope.view.loading         = false

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

    buildBarCharts: (aggregated) ->
        charts = {}
        for metricId, data of aggregated
            labels = data.values.map (v) -> v.group_code
            values = data.values.map (v) -> Math.round((v.value or 0) * 10000) / 100
            colors = labels.map (_, i) => @.GROUP_COLORS[i % @.GROUP_COLORS.length]
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

    refresh: ->
        @scope.view.refreshing = true
        @.load(true).finally =>
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
        @scope.editionId = parseInt(@params.editionId, 10)
        @scope.groupId   = parseInt(@params.groupId, 10)

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

        @scope.refresh = => @.refresh()

        @.load()

    load: (force=false) ->
        @scope.view.loading = true
        @scope.view.error = null

        url    = @urls.resolve("academics-edition-dashboard", @scope.editionId)
        params = if force then {refresh: "1"} else {}

        return @http.get(url, params).then (response) =>
            data  = response.data
            rawGroup = _.find(data.groups or [], (g) => g.group_id == @scope.groupId)

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
            @scope.view.students          = group.students or []
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
        @scope.editionId = parseInt(@params.editionId, 10)

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

        @scope.save   = => @.save()
        @scope.toggle = (metric, field) => metric[field] = !metric[field]

        @.load()

    load: ->
        @scope.view.loading = true
        @scope.view.error   = null

        dashboardReq = @http.get(
            @urls.resolve("academics-edition-dashboard", @scope.editionId),
            {raw: "1"}
        ).then (r) -> r.data

        policyReq = @http.get(
            @urls.resolve("academics-metrics-policies"),
            {course_edition_id: @scope.editionId}
        ).then (r) -> r.data

        @q.all([dashboardReq, policyReq]).then ([dashboard, policies]) =>
            @scope.view.edition =
                id:  dashboard.course_edition_id
                key: dashboard.course_edition_key

            policy   = policies[0] or {}
            hiddenIds          = policy.hidden_metric_ids or []
            visibleStudentIds  = policy.visible_to_students_metric_ids or []

            @scope.view.policyId              = policy.id or null
            @scope.view.allowStudentDrilldown = if policy.allow_student_drilldown? then policy.allow_student_drilldown else true

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
                    allMetrics[metricId] ?=
                        id:             metricId
                        name:           metricName
                        classification: metric.classification
                        hidden:         hiddenIds.indexOf(metricId) >= 0
                        visibleToStudents: visibleStudentIds.indexOf(metricId) >= 0

            metrics = _.values(allMetrics)
            @scope.view.projectMetrics = metrics.filter (m) -> m.classification == 'project'
            @scope.view.teamMetrics    = metrics.filter (m) -> m.classification == 'team'
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

    save: ->
        @scope.view.saving    = true
        @scope.view.saved     = false
        @scope.view.saveError = null

        allMetrics = @scope.view.projectMetrics.concat(@scope.view.teamMetrics)

        payload =
            hidden_metric_ids:              allMetrics.filter((m) -> m.hidden).map (m) -> m.id
            visible_to_students_metric_ids: allMetrics.filter((m) -> m.visibleToStudents).map (m) -> m.id
            allow_student_drilldown:        @scope.view.allowStudentDrilldown

        req =
            if @scope.view.policyId
                payload.course_edition_id = @scope.editionId
                @http.patch(
                    @urls.resolve("academics-metrics-policy-detail", @scope.view.policyId),
                    payload
                )
            else
                payload.course_edition_id = @scope.editionId
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
