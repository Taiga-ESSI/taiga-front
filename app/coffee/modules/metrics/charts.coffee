###
# CREADOR POR: POL ALCOVERRO
# Descripción: Directivas Chart.js para visualizar métricas de Learning Dashboard (radar, gauge, pie, líneas).
#              Versión ajustada para registrar Chart.js dinámicamente en Taiga Front.
###

taiga = @.taiga

module = angular.module("taigaMetrics")

chartReadyPromise = null

ensureChartReady = ->
    return chartReadyPromise if chartReadyPromise?

    chartReadyPromise = new Promise (resolve, reject) ->
        maxAttempts = 100
        attempts = 0
        
        registerIfNeeded = ->
            if window.Chart? and window.Chart.register? and window.Chart.registerables? and !window.Chart._taigaMetricsRegistered
                try
                    window.Chart.register.apply(window.Chart, window.Chart.registerables)
                    window.Chart._taigaMetricsRegistered = true
                    console.log("✓ Chart.js registered successfully")
                catch error
                    console.error("Error registering Chart.js:", error)

        checkChart = ->
            attempts++
            if window.Chart?
                console.log("✓ Chart.js found, version:", window.Chart.version)
                registerIfNeeded()
                resolve(window.Chart)
            else if attempts < maxAttempts
                console.log("Waiting for Chart.js... attempt #{attempts}")
                setTimeout(checkChart, 100)
            else
                console.error("Chart.js not loaded after #{maxAttempts} attempts")
                reject(new Error("Chart.js not available"))

        checkChart()

    return chartReadyPromise

getChartMajorVersion = (ChartLib) ->
    version = ChartLib?.version
    return 0 unless version?
    major = parseInt(version.toString().split(".")[0], 10)
    return if isNaN(major) then 0 else major

#############################################################################
## Radar Chart Directive - FIXED
#############################################################################

RadarChartDirective = ($parse, $timeout) ->
    link = (scope, element, attrs) ->
        console.log("RadarChart directive linking, initial data:", scope.data)
        
        canvasId = "radar-chart-#{Date.now()}-#{Math.random().toString(36).substr(2, 9)}"
        canvas = document.createElement('canvas')
        canvas.id = canvasId
        canvas.width = 400
        canvas.height = 400
        element.append(canvas)
        
        chart = null
        isRendering = false
        
        destroyChart = ->
            if chart?
                try
                    chart.destroy()
                    console.log("Chart destroyed for:", canvasId)
                catch e
                    console.error("Error destroying chart:", e)
                chart = null
        
        renderChart = (data) ->
            console.log("RadarChart renderChart called with data:", data)
            
            if !data or !data.datasets or data.datasets.length is 0
                console.warn("No valid data for radar chart")
                destroyChart()
                return
            
            return if isRendering
            isRendering = true
            
            ensureChartReady().then (ChartLib) ->
                console.log("Chart.js ready, rendering radar chart for:", canvasId)
                
                # Increase timeout to ensure DOM is fully rendered and stable
                $timeout ->
                    try
                        ctx = canvas.getContext('2d')
                        if !ctx
                            console.error("Could not get canvas context for:", canvasId)
                            isRendering = false
                            return
                        
                        destroyChart()
                        
                        majorVersion = getChartMajorVersion(ChartLib)
                        console.log("Creating radar chart, Chart.js version:", majorVersion)
                        
                        baseConfig =
                            type: 'radar'
                            data:
                                labels: data.labels or [
                                    'Assigned Tasks'
                                    'Commits'
                                    'Modified Lines'
                                ]
                                datasets: data.datasets or []
                            options:
                                responsive: true
                                maintainAspectRatio: true
                        
                        if majorVersion >= 3
                            baseConfig.options.scales =
                                r:
                                    beginAtZero: true
                                    min: 0
                                    max: 100
                                    ticks:
                                        stepSize: 20
                                        color: '#1e293b'
                                        callback: (value) -> "#{value}%"
                                    pointLabels:
                                        color: '#0f172a'
                                        font:
                                            size: 12
                                            weight: 600
                                        # Split long labels into multiple lines for better readability
                                        callback: (label) ->
                                            if not label or typeof label isnt 'string'
                                                return label
                                            # Split labels longer than 15 characters
                                            if label.length > 15
                                                words = label.split(' ')
                                                lines = []
                                                currentLine = ''
                                                for word in words
                                                    if currentLine.length + word.length + 1 <= 15
                                                        currentLine = if currentLine then "#{currentLine} #{word}" else word
                                                    else
                                                        lines.push(currentLine) if currentLine
                                                        currentLine = word
                                                lines.push(currentLine) if currentLine
                                                return lines
                                            return label
                                    grid:
                                        color: 'rgba(30, 41, 59, 0.15)'
                            baseConfig.options.plugins =
                                legend:
                                    # Pol Alcoverro - Leyenda desactivada para evitar selector interno en radar chart
                                    display: false
                                    # display: (data.datasets ? []).length > 1
                                    # position: 'bottom'
                                    # labels:
                                    #     color: '#1e293b'
                                    #     font:
                                    #         size: 12
                                    #         weight: 500
                                tooltip:
                                    callbacks:
                                        label: (context) ->
                                            label = context.dataset?.label or ''
                                            parts = []
                                            parts.push("#{label}:") if label
                                            value = context.parsed?.r
                                            parts.push("#{Number(value or 0).toFixed(2)}%")
                                            parts.join(' ')
                        else
                            baseConfig.options.scale =
                                ticks:
                                    beginAtZero: true
                                    max: 100
                                    stepSize: 20
                                    fontColor: '#1e293b'
                                    callback: (value) -> "#{value}%"
                                pointLabels:
                                    fontColor: '#0f172a'
                                    fontSize: 12
                                    # Split long labels for better readability
                                    callback: (label) ->
                                        if not label or typeof label isnt 'string'
                                            return label
                                        if label.length > 15
                                            words = label.split(' ')
                                            lines = []
                                            currentLine = ''
                                            for word in words
                                                if currentLine.length + word.length + 1 <= 15
                                                    currentLine = if currentLine then "#{currentLine} #{word}" else word
                                                else
                                                    lines.push(currentLine) if currentLine
                                                    currentLine = word
                                            lines.push(currentLine) if currentLine
                                            return lines
                                        return label
                                gridLines:
                                    color: 'rgba(30, 41, 59, 0.15)'
                            baseConfig.options.legend =
                                # Pol Alcoverro - Leyenda desactivada para evitar selector interno en radar chart
                                display: false
                                # display: (data.datasets ? []).length > 1
                                # position: 'bottom'
                                # labels:
                                #     fontColor: '#1e293b'
                                #     fontSize: 12
                            baseConfig.options.tooltips =
                                callbacks:
                                    label: (tooltipItem, chartData) ->
                                        dataset = chartData?.datasets?[tooltipItem.datasetIndex]
                                        label = dataset?.label or ''
                                        value = tooltipItem?.yLabel ? tooltipItem?.value ? tooltipItem?.parsed
                                        valueNumber = Number(value or 0)
                                        "#{label}: #{valueNumber.toFixed(2)}%"
                        
                        console.log("Creating chart with config:", baseConfig)
                        chart = new ChartLib(ctx, baseConfig)
                        console.log("✓ Radar chart created successfully:", canvasId)
                        
                    catch error
                        console.error("Error creating radar chart:", error)
                    finally
                        isRendering = false
                , 250  # Increased timeout to ensure DOM stability
            .catch (error) ->
                console.error("Chart.js not available:", error)
                isRendering = false
        
        # Initial render if data is already available
        $timeout ->
            if scope.data and scope.data.datasets and scope.data.datasets.length > 0
                console.log("RadarChart initial render with:", scope.data)
                renderChart(scope.data)
        , 0
        
        # Watch for data changes - only re-render if data actually changes
        scope.$watch 'data', (newVal, oldVal) ->
            # Skip if it's the initial watch trigger (newVal === oldVal)
            return if newVal is oldVal and chart?
            
            if newVal and newVal.datasets and newVal.datasets.length > 0
                console.log("RadarChart data changed, re-rendering")
                renderChart(newVal)
            else if !newVal
                destroyChart()
        , false  # Shallow watch - only watch reference changes
        
        scope.$on '$destroy', ->
            console.log("RadarChart directive destroyed:", canvasId)
            destroyChart()
    
    return {
        restrict: 'E'
        link: link
        scope: {
            data: '='
        }
    }

module.directive("tgRadarChart", ["$parse", "$timeout", RadarChartDirective])

#############################################################################
## Speedometer/Gauge Chart Directive - FIXED
#############################################################################

SpeedometerChartDirective = ($parse, $timeout) ->
    link = (scope, element, attrs) ->
        console.log("Speedometer directive linking")
        
        canvasId = "speedometer-#{Date.now()}-#{Math.random().toString(36).substr(2, 9)}"
        canvas = document.createElement('canvas')
        canvas.id = canvasId
        canvas.width = 400
        canvas.height = 280
        element.append(canvas)
        
        chart = null
        isRendering = false
        
        destroyChart = ->
            if chart?
                try
                    chart.destroy()
                catch e
                    console.error("Error destroying speedometer:", e)
                chart = null
        
        formatScaleValue = (value, unit) ->
            return "" unless isFinite(value)

            absValue = Math.abs(value)
            decimals = if absValue >= 100
                0
            else if absValue >= 10
                1
            else
                2

            formatted = value.toFixed(decimals)
            formatted = formatted.replace(/\.0+$/, '')
            formatted = formatted.replace(/(\.\d*[1-9])0+$/, '$1')

            if unit? and unit.length > 0
                "#{formatted}#{unit}"
            else
                formatted

        # Solid colors only - NO transparency
        SOLID_BLUE = '#2563EB'
        SOLID_GREY = 'rgb(203, 213, 225)'
        


        buildPaletteDataset = (segments, fallbackColor, maxRangeRatio = 1) ->
            # Only process when we have valid palette segments (typically from EXTERNAL provider)
            # The segments already come complete from buildMetricCategorySegments
            return null unless Array.isArray(segments) and segments.length > 0

            entries = []
            totalRatio = 0

            for segment in segments when segment?
                segmentValue = Number(segment.value)
                continue unless isFinite(segmentValue) and segmentValue > 0
                
                # Use colors directly from API - they already come without transparency
                colorValue = segment.color or SOLID_BLUE
                
                entries.push({
                    ratio: segmentValue
                    color: colorValue
                })
                totalRatio += segmentValue

            return null unless entries.length

            # The segments already cover the full range, no need to add remainder
            # Just normalize to 100% for the chart
            totalRatio = 1 if totalRatio <= 0

            scaleFactor = 100 / totalRatio
            data = entries.map (entry) -> Math.max(0, entry.ratio * scaleFactor)
            colors = entries.map (entry) -> entry.color

            return {
                data: data
                colors: colors
            }

        renderChart = (value, label, maxValue, rawValue, unit, metricKey, customColor, paletteSegments) ->
            console.log("Speedometer renderChart:", value, label, "customColor:", customColor, "paletteSegments:", paletteSegments)
            
            return if isRendering
            isRendering = true
            
            ensureChartReady().then (ChartLib) ->
                $timeout ->
                    try
                        ctx = canvas.getContext('2d')
                        if !ctx
                            console.error("Could not get canvas context for speedometer")
                            isRendering = false
                            return
                        
                        destroyChart()

                        maxRefRatio = parseFloat(maxValue)
                        if !isFinite(maxRefRatio) or maxRefRatio <= 0
                            maxRefRatio = 1

                        hasCustomScale = true

                        inputRatio = parseFloat(value)
                        inputRatio = 0 unless isFinite(inputRatio)

                        ratioClamped = Math.max(0, Math.min(inputRatio, maxRefRatio))
                        normalized = if maxRefRatio > 0 then (ratioClamped / maxRefRatio) * 100 else 0

                        absoluteRatio = parseFloat(rawValue)
                        if !isFinite(absoluteRatio)
                            absoluteRatio = ratioClamped
                        absoluteRatio = Math.max(0, absoluteRatio)

                        # Use palette segments if provided (EXTERNAL), otherwise use solid colors
                        paletteDataset = buildPaletteDataset(paletteSegments, SOLID_GREY, maxRefRatio)
                        
                        # Determine gauge colors - always solid, no transparency
                        gaugeBaseColor = SOLID_BLUE
                        gaugeRemainderColor = SOLID_GREY
                        
                        # If custom color provided, use it
                        if typeof customColor is "string" and customColor.trim().length > 0
                            gaugeBaseColor = customColor.trim()
                        # If gradient style available (internal metrics), use it
                        else
                            gaugeFillStyle = getGradientForValue(ctx, normalized, label, metricKey)
                            if gaugeFillStyle? and typeof gaugeFillStyle is "object" and gaugeFillStyle.fill
                                gaugeBaseColor = gaugeFillStyle.fill
                                gaugeRemainderColor = gaugeFillStyle.remainder

                        datasetData = []
                        datasetColors = []

                        if paletteDataset?
                            # Use palette segments if explicitly provided (traffic light or segments)
                            datasetData = paletteDataset.data
                            datasetColors = paletteDataset.colors
                        else
                            # Partial fill rendering (needle + backdrop with gradient/solid)
                            datasetData = [normalized, Math.max(100 - normalized, 0)]
                            datasetColors = [gaugeBaseColor, gaugeRemainderColor]
                        
                        datasetObject = {
                            data: datasetData
                            backgroundColor: datasetColors
                            hoverBackgroundColor: datasetColors
                            borderWidth: 0
                            hoverBorderWidth: 0
                            hoverOffset: 0
                            circumference: 180
                            rotation: 270
                            cutout: '75%'
                            borderRadius: 0
                        }

                        datasetObject._taigaContext =
                            normalized: normalized
                            hasCustomScale: hasCustomScale
                            maxRef: maxRefRatio
                            unit: unit
                            absolute: absoluteRatio
                            label: label
                            pointerColor: '#000000'
                            displayAsRatio: true
                            ratioValue: ratioClamped

                        config = {
                            type: 'doughnut'
                            data: {
                                datasets: [datasetObject]
                            }
                            options: {
                                responsive: true
                                maintainAspectRatio: true
                                aspectRatio: 1.6
                                layout: {
                                    padding: {
                                        bottom: 20
                                    }
                                }
                                plugins: {
                                    legend: {
                                        display: false
                                    }
                                    tooltip: {
                                        enabled: false
                                    }
                                }
                            }
                            plugins: [{
                                id: 'gaugeEnhancements'
                                afterDatasetDraw: (chart) =>
                                    meta = chart.getDatasetMeta(0)
                                    firstArc = meta?.data?[0]
                                    dataset = chart.config?.data?.datasets?[0]
                                    contextInfo = dataset?._taigaContext or {}
                                    return unless firstArc?

                                    ctx = chart.ctx
                                    cx = firstArc.x
                                    cy = firstArc.y
                                    outerRadius = firstArc.outerRadius or 0
                                    innerRadius = firstArc.innerRadius or 0

                                    gaugeStart = null
                                    gaugeEnd = null

                                    if meta?.data and meta.data.length > 0
                                        for arcItem in meta.data when arcItem?
                                            startAngle = arcItem.startAngle
                                            endAngle = arcItem.endAngle
                                            continue unless isFinite(startAngle) and isFinite(endAngle)
                                            gaugeStart = startAngle if gaugeStart is null or startAngle < gaugeStart
                                            gaugeEnd = endAngle if gaugeEnd is null or endAngle > gaugeEnd

                                    unless gaugeStart? and gaugeEnd?
                                        rotationDeg = dataset?.rotation or 270
                                        circumferenceDeg = dataset?.circumference or 180
                                        gaugeStart = rotationDeg * Math.PI / 180
                                        gaugeEnd = gaugeStart + (circumferenceDeg * Math.PI / 180)

                                    normalizedValue = contextInfo.normalized or 0
                                    span = gaugeEnd - gaugeStart
                                    pointerAngle = gaugeStart + (Math.max(0, Math.min(100, normalizedValue)) / 100) * span

                                    ctx.save()
                                    drawScaleMarks(
                                        ctx, cx, cy, outerRadius, innerRadius,
                                        contextInfo.hasCustomScale,
                                        contextInfo.maxRef,
                                        contextInfo.unit,
                                        contextInfo.displayAsRatio
                                    )

                                    drawCenterText(
                                        ctx, cx, cy, normalizedValue,
                                        contextInfo.label,
                                        contextInfo.absolute,
                                        contextInfo.unit,
                                        contextInfo.hasCustomScale,
                                        contextInfo.maxRef
                                    )

                                    drawPointer(
                                        ctx, cx, cy, pointerAngle,
                                        innerRadius, outerRadius,
                                        contextInfo.pointerColor
                                    )
                                    ctx.restore()
                            }]
                        }
                        
                        chart = new ChartLib(ctx, config)
                        console.log("✓ Speedometer created")
                        
                    catch error
                        console.error("Error creating speedometer:", error)
                    finally
                        isRendering = false
                , 250  # Increased timeout for stability
        
        drawScaleMarks = (ctx, cx, cy, outerRadius, innerRadius, hasCustomScale, maxRef, unit, displayAsRatio = false) ->
            ctx.strokeStyle = 'rgba(30, 41, 59, 0.4)'
            ctx.lineWidth = 2
            
            # Draw marks at 0%, 50%, 100% only (removed 25% and 75%)
            for i in [0, 2, 4]
                angle = Math.PI + (i * Math.PI / 4)  # From 180° to 0°
                startRadius = outerRadius + 5
                endRadius = outerRadius + 15
                
                x1 = cx + startRadius * Math.cos(angle)
                y1 = cy + startRadius * Math.sin(angle)
                x2 = cx + endRadius * Math.cos(angle)
                y2 = cy + endRadius * Math.sin(angle)
                
                ctx.beginPath()
                ctx.moveTo(x1, y1)
                ctx.lineTo(x2, y2)
                ctx.stroke()
                
                # Draw scale labels at strategic positions
                labelRadius = outerRadius + 28
                labelX = cx + labelRadius * Math.cos(angle)
                labelY = cy + labelRadius * Math.sin(angle)

                if hasCustomScale
                    labelValue = (maxRef or 0) * (i / 4)
                else
                    labelValue = i * 25

                if displayAsRatio
                    labelText = Number(labelValue or 0).toFixed(2)
                else
                    labelText = formatScaleValue(labelValue, if hasCustomScale then unit else "%")
                
                ctx.fillStyle = '#1e293b'
                ctx.font = 'bold 12px sans-serif'
                ctx.textAlign = 'center'
                ctx.textBaseline = 'middle'
                ctx.fillText(labelText, labelX, labelY)
        
        drawCenterText = (ctx, cx, cy, normalized, label, absolute, unit, hasCustomScale, maxRef) ->
            # Center readout intentionally suppressed
            return

        
        drawPointer = (ctx, cx, cy, angle, innerRadius, outerRadius, pointerColor) ->
            pointerRadius = innerRadius + (outerRadius - innerRadius) * 0.8
            pointerWidth = 6
            headLength = 10
            
            endX = cx + pointerRadius * Math.cos(angle)
            endY = cy + pointerRadius * Math.sin(angle)
            
            # Draw pointer shadow
            ctx.shadowColor = 'rgba(0, 0, 0, 0.3)'
            ctx.shadowBlur = 8
            ctx.shadowOffsetX = 2
            ctx.shadowOffsetY = 2
            
            # Draw pointer line with gradient
            ctx.lineWidth = pointerWidth
            ctx.lineCap = 'round'
            ctx.strokeStyle = pointerColor or '#000000'
            
            ctx.beginPath()
            ctx.moveTo(cx, cy)
            ctx.lineTo(endX, endY)
            ctx.stroke()
            
            # Reset shadow
            ctx.shadowColor = 'transparent'
            ctx.shadowBlur = 0
            ctx.shadowOffsetX = 0
            ctx.shadowOffsetY = 0
            
            # Draw arrow head
            ctx.fillStyle = pointerColor or '#000000'
            ctx.beginPath()
            ctx.moveTo(endX, endY)
            ctx.lineTo(
                endX - headLength * Math.cos(angle - Math.PI / 8),
                endY - headLength * Math.sin(angle - Math.PI / 8)
            )
            ctx.lineTo(
                endX - headLength * Math.cos(angle + Math.PI / 8),
                endY - headLength * Math.sin(angle + Math.PI / 8)
            )
            ctx.closePath()
            ctx.fill()
            
            # Draw center circle with shadow
            ctx.shadowColor = 'rgba(0, 0, 0, 0.2)'
            ctx.shadowBlur = 4
            ctx.fillStyle = '#000000'
            ctx.beginPath()
            ctx.arc(cx, cy, 8, 0, Math.PI * 2)
            ctx.fill()
            
            # Inner white circle
            ctx.shadowColor = 'transparent'
            ctx.fillStyle = '#ffffff'
            ctx.beginPath()
            ctx.arc(cx, cy, 4, 0, Math.PI * 2)
            ctx.fill()
        
        getGradientForValue = (ctx, value, label, metricKey) ->
            identifier = metricKey or label or ""
            normalizedIdentifier = identifier.toString().toLowerCase()
            
            console.log("Gauge check:", {label: label, key: metricKey, normalized: normalizedIdentifier})

            # Identify if it's an internal metric and what type of behavior it has
            # "Worsening" means high value is bad (Green -> Red)
            # "Improving" means high value is good (Red -> Green)
            isWorsening = /unassigned|deviation|commits_anonymous|pattern_check/.test(normalizedIdentifier)
            isInternal = isWorsening or /acceptance_criteria|closed_tasks_with_ae|commits_sd|commits_taskreference|tasks_sd|tasks_with_ee/.test(normalizedIdentifier)
            isAssignedMetric = /assigned|asignad|assign|asign/i.test(normalizedIdentifier) and not /unassigned/i.test(normalizedIdentifier)

            console.log "Gauge Check:", {
                identifier: identifier,
                normalized: normalizedIdentifier,
                isAssigned: isAssignedMetric,
                isInternal: isInternal,
                value: value
            }

            if not isInternal and not isAssignedMetric
                # Solid blue fill - NO transparency
                return {
                    fill: 'rgb(37, 99, 235)'
                    remainder: SOLID_GREY
                }

            gradient = ctx.createLinearGradient(0, 0, 400, 0)
            remainderGradient = ctx.createLinearGradient(0, 0, 400, 0)

            if isAssignedMetric
                # Custom ranges: 0-10 Orange, 10-30 Green, 30-50 Orange, 50+ Red
                
                # Remainder gradient (background track) - SOLID colors
                remainderGradient.addColorStop(0, 'rgb(251, 191, 36)')   # 0-10 Orange
                remainderGradient.addColorStop(0.2, 'rgb(34, 197, 94)')  # 10-30 Green
                remainderGradient.addColorStop(0.4, 'rgb(251, 191, 36)') # 30-50 Orange
                remainderGradient.addColorStop(1, 'rgb(239, 68, 68)')    # 50+ Red

                if value < 10
                    # 0 - 10: Orange - SOLID
                    gradient.addColorStop(0, 'rgb(251, 191, 36)')
                    gradient.addColorStop(1, 'rgb(245, 158, 11)')
                else if value < 30
                    # 10 - 30: Green - SOLID
                    gradient.addColorStop(0, 'rgb(34, 197, 94)')
                    gradient.addColorStop(1, 'rgb(22, 163, 74)')
                else if value < 50
                    # 30 - 50: Orange - SOLID
                    gradient.addColorStop(0, 'rgb(251, 191, 36)')
                    gradient.addColorStop(1, 'rgb(245, 158, 11)')
                else
                    # 50 - 100: Red - SOLID
                    gradient.addColorStop(0, 'rgb(239, 68, 68)')
                    gradient.addColorStop(1, 'rgb(220, 38, 38)')

                return {
                    fill: gradient
                    remainder: remainderGradient
                }

            if isWorsening
                # Green -> Orange -> Red - SOLID colors
                remainderGradient.addColorStop(0, 'rgb(34, 197, 94)')
                remainderGradient.addColorStop(0.5, 'rgb(251, 191, 36)')
                remainderGradient.addColorStop(1, 'rgb(239, 68, 68)')

                if value < 33
                    # Low unassigned percentage -> green - SOLID
                    gradient.addColorStop(0, 'rgb(34, 197, 94)')
                    gradient.addColorStop(1, 'rgb(22, 163, 74)')
                else if value < 66
                    # Mid values -> orange - SOLID
                    gradient.addColorStop(0, 'rgb(251, 191, 36)')
                    gradient.addColorStop(1, 'rgb(245, 158, 11)')
                else
                    # High unassigned percentage -> red - SOLID
                    gradient.addColorStop(0, 'rgb(239, 68, 68)')
                    gradient.addColorStop(1, 'rgb(220, 38, 38)')
            else
                # Red -> Orange -> Green - SOLID colors
                remainderGradient.addColorStop(0, 'rgb(239, 68, 68)')
                remainderGradient.addColorStop(0.5, 'rgb(251, 191, 36)')
                remainderGradient.addColorStop(1, 'rgb(34, 197, 94)')

                if value < 33
                    # Low value -> red - SOLID
                    gradient.addColorStop(0, 'rgb(239, 68, 68)')
                    gradient.addColorStop(1, 'rgb(220, 38, 38)')
                else if value < 66
                    # Mid values -> orange - SOLID
                    gradient.addColorStop(0, 'rgb(251, 191, 36)')
                    gradient.addColorStop(1, 'rgb(245, 158, 11)')
                else
                    # High value -> green - SOLID
                    gradient.addColorStop(0, 'rgb(34, 197, 94)')
                    gradient.addColorStop(1, 'rgb(22, 163, 74)')

            return {
                fill: gradient
                remainder: remainderGradient
            }
        
        scheduleRender = ->
            return unless scope.value? or scope.rawValue?
            renderChart(scope.value, scope.label, scope.maxValue, scope.rawValue, scope.unit, scope.metricKey, scope.color, scope.palette)
        
        scope.$watchGroup ['value', 'label', 'maxValue', 'rawValue', 'unit', 'metricKey', 'color', 'palette'], ->
            scheduleRender()
        
        scope.$on '$destroy', ->
            destroyChart()
    
    return {
        restrict: 'E'
        link: link
        scope: {
            value: '='
            label: '@'
            maxValue: '=?'
            rawValue: '=?'
            unit: '@?'
            metricKey: '@?'
            color: '=?'
            palette: '=?'
        }
    }

module.directive("tgSpeedometerChart", ["$parse", "$timeout", SpeedometerChartDirective])

#############################################################################
## Pie Chart Directive - FIXED
#############################################################################

PieChartDirective = ($parse, $timeout) ->
    link = (scope, element, attrs) ->
        console.log("PieChart directive linking")
        
        canvasId = "pie-#{Date.now()}-#{Math.random().toString(36).substr(2, 9)}"
        canvas = document.createElement('canvas')
        canvas.id = canvasId
        canvas.width = 400
        canvas.height = 400
        element.append(canvas)
        
        chart = null
        isRendering = false
        
        destroyChart = ->
            if chart?
                try
                    chart.destroy()
                catch e
                   	console.error("Error destroying pie chart:", e)
                chart = null
        
        renderChart = (data) ->
            console.log("PieChart renderChart:", data)
            
            if !data
                destroyChart()
                return
            
            return if isRendering
            isRendering = true
            
            ensureChartReady().then (ChartLib) ->
                $timeout ->
                    try
                        ctx = canvas.getContext('2d')
                        if !ctx
                            console.error("Could not get canvas context for pie")
                            isRendering = false
                            return
                        
                        destroyChart()
                        
                        config = {
                            type: 'doughnut'
                            data: {
                                labels: data.labels || []
                                datasets: [{
                                    data: data.values || []
                                    backgroundColor: data.colors || generateColors(data.labels?.length || 0)
                                    borderWidth: 2
                                    borderColor: data.borderColors || '#fff'
                                }]
                            }
                            options:
                                responsive: true
                                maintainAspectRatio: true
                                plugins:
                                    legend:
                                        display: true
                                        position: 'bottom'
                                        labels:
                                            color: '#1e293b'
                                            font:
                                                size: 12
                                                weight: 500
                                    tooltip:
                                        callbacks:
                                            label: (context) ->
                                                label = context.label || ''
                                                value = context.parsed || 0
                                                total = 0
                                                for point in context.dataset?.data or []
                                                    total += point or 0
                                                percentage = if total > 0 then ((value / total) * 100).toFixed(1) else "0.0"
                                                return label + ': ' + value.toFixed(2) + ' (' + percentage + '%)'
                        }
                        
                        chart = new ChartLib(ctx, config)
                        console.log("✓ Pie chart created")
                        
                    catch error
                        console.error("Error creating pie chart:", error)
                   	finally
                        isRendering = false
                , 100
        
        generateColors = (count) ->
            colors = [
                'rgba(255, 99, 132, 0.8)'
                'rgba(54, 162, 235, 0.8)'
                'rgba(255, 206, 86, 0.8)'
                'rgba(75, 192, 192, 0.8)'
                'rgba(153, 102, 255, 0.8)'
                'rgba(255, 159, 64, 0.8)'
                'rgba(199, 199, 199, 0.8)'
                'rgba(83, 102, 255, 0.8)'
                'rgba(255, 99, 255, 0.8)'
                'rgba(99, 255, 132, 0.8)'
            ]
            colors.slice(0, count)
        
        scope.$watch 'data', (newVal, oldVal) ->
            if newVal
                renderChart(newVal)
            else
                destroyChart()
        , true
        
        scope.$on '$destroy', ->
            destroyChart()
    
    return {
        restrict: 'E'
        link: link
        scope: {
            data: '='
        }
    }

module.directive("tgPieChart", ["$parse", "$timeout", PieChartDirective])

#############################################################################
## Bar Chart Directive
#############################################################################

BarChartDirective = ($parse, $timeout) ->
    link = (scope, element, attrs) ->
        console.log("BarChart directive linking")
        
        canvasId = "bar-#{Date.now()}-#{Math.random().toString(36).substr(2, 9)}"
        canvas = document.createElement('canvas')
        canvas.id = canvasId
        canvas.width = 600
        canvas.height = 400
        element.append(canvas)
        
        chart = null
        isRendering = false
        
        destroyChart = ->
            if chart?
                try
                    chart.destroy()
                catch e
                    console.error("Error destroying bar chart:", e)
                chart = null
        
        renderChart = (data) ->
            console.log("BarChart renderChart:", data)
            
            if !data or !(data.datasets and data.datasets.length > 0)
                destroyChart()
                return
            
            return if isRendering
            isRendering = true
            
            ensureChartReady().then (ChartLib) ->
                $timeout ->
                    try
                        ctx = canvas.getContext('2d')
                        if !ctx
                            console.error("Could not get canvas context for bar chart")
                            isRendering = false
                            return
                        
                        destroyChart()
                        
                        config =
                            type: 'bar'
                            data:
                                labels: data.labels or []
                                datasets: data.datasets or []
                            options:
                                responsive: true
                                maintainAspectRatio: true
                                layout:
                                    padding:
                                        top: 16
                                        right: 8
                                        left: 8
                                scales:
                                    x:
                                        grid:
                                            display: false
                                        ticks:
                                            color: '#1e293b'
                                            font:
                                                size: 12
                                                weight: 500
                                    y:
                                        beginAtZero: true
                                        min: 0
                                        max: 100
                                        ticks:
                                            stepSize: 20
                                            color: '#1e293b'
                                            callback: (value) -> "#{value}%"
                                        grid:
                                            color: 'rgba(30, 41, 59, 0.12)'
                                plugins:
                                    legend:
                                        display: true
                                        position: 'top'
                                        labels:
                                            color: '#1e293b'
                                            font:
                                                size: 12
                                                weight: 500
                                    tooltip:
                                        callbacks:
                                            label: (context) ->
                                                label = context.dataset?.label or ''
                                                value = context.parsed?.y
                                                parts = []
                                                parts.push("#{label}:") if label
                                                parts.push("#{Number(value or 0).toFixed(2)}%")
                                                parts.join(' ')

                        if data?.options?
                            customOptions = angular.copy(data.options)
                            if angular.merge?
                                config.options = angular.merge({}, config.options, customOptions)
                            else
                                config.options = angular.extend({}, config.options, customOptions)
                        
                        chart = new ChartLib(ctx, config)
                        console.log("✓ Bar chart created")
                        
                    catch error
                        console.error("Error creating bar chart:", error)
                    finally
                        isRendering = false
                , 150
            .catch (error) ->
                console.error("Chart.js not available for bar chart:", error)
                isRendering = false
        
        scope.$watch 'data', (newVal, oldVal) ->
            return if newVal is oldVal and chart?
            
            if newVal and newVal.datasets and newVal.datasets.length > 0
                renderChart(newVal)
            else
                destroyChart()
        , false
        
        scope.$on '$destroy', ->
            destroyChart()
    
    return {
        restrict: 'E'
        link: link
        scope: {
            data: '='
        }
    }

module.directive("tgBarChart", ["$parse", "$timeout", BarChartDirective])

#############################################################################
## Line Chart Directive - FIXED
#############################################################################

LineChartDirective = ($parse, $timeout) ->
    link = (scope, element, attrs) ->
        console.log("LineChart directive linking")
        
        canvasId = "line-#{Date.now()}-#{Math.random().toString(36).substr(2, 9)}"
        canvas = document.createElement('canvas')
        canvas.id = canvasId
        canvas.width = 600
        canvas.height = 400
        element.append(canvas)
        
        chart = null
        isRendering = false
        
        destroyChart = ->
            if chart?
                try
                    chart.destroy()
                catch e
                   	console.error("Error destroying line chart:", e)
                chart = null
        
        renderChart = (data) ->
            console.log("LineChart renderChart:", data)
            
            if !data
                destroyChart()
                return
            
            return if isRendering
            isRendering = true
            
            ensureChartReady().then (ChartLib) ->
                $timeout ->
                    try
                        ctx = canvas.getContext('2d')
                        if !ctx
                            console.error("Could not get canvas context for line")
                            isRendering = false
                            return
                        
                        destroyChart()
                        
                        config = {
                            type: 'line'
                            data: {
                                labels: data.labels || []
                                datasets: data.datasets || []
                            }
                            options: {
                                responsive: true
                                maintainAspectRatio: true
                                scales: {
                                    y: {
                                        beginAtZero: true
                                        min: 0
                                        max: data.maxValue || 100
                                        ticks: {
                                            color: '#1e293b'
                                            callback: (value) ->
                                                if data.isPercentage
                                                    return value + '%'
                                                return value
                                        }
                                        grid: {
                                            color: 'rgba(30, 41, 59, 0.1)'
                                        }
                                    }
                                    x: {
                                        display: true
                                        ticks: {
                                            color: '#1e293b'
                                        }
                                        grid: {
                                            color: 'rgba(30, 41, 59, 0.1)'
                                        }
                                    }
                                }
                                plugins: {
                                    legend: {
                                        display: data.datasets?.length > 1
                                        position: 'bottom'
                                        labels: {
                                            color: '#1e293b'
                                            font: {
                                                size: 12
                                                weight: 500
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        chart = new ChartLib(ctx, config)
                        console.log("✓ Line chart created")
                        
                    catch error
                        console.error("Error creating line chart:", error)
                   	finally
                        isRendering = false
                , 100
        
        scope.$watch 'data', (newVal, oldVal) ->
            if newVal
                renderChart(newVal)
            else
                destroyChart()
        , true
        
        scope.$on '$destroy', ->
            destroyChart()
    
    return {
        restrict: 'E'
        link: link
        scope: {
            data: '='
        }
    }

module.directive("tgLineChart", ["$parse", "$timeout", LineChartDirective])

#############################################################################
## Area Chart Directive - For Historical Metrics
## Displays time-series data as an area chart with a line overlay
#############################################################################

AreaChartDirective = ($parse, $timeout) ->
    link = (scope, element, attrs) ->
        canvasId = "area-chart-#{Date.now()}-#{Math.random().toString(36).substr(2, 9)}"
        canvas = document.createElement('canvas')
        canvas.id = canvasId
        canvas.width = 600
        canvas.height = 400
        element.append(canvas)
        
        chart = null
        isRendering = false
        
        destroyChart = ->
            if chart?
                try
                    chart.destroy()
                catch e
                    console.error("Error destroying area chart:", e)
                chart = null
        
        renderChart = (data) ->
            # Validate data structure
            if !data or !data.labels or !data.datasets or data.datasets.length is 0
                console.warn("No valid data for area chart")
                destroyChart()
                return
            
            return if isRendering
            isRendering = true
            
            ensureChartReady().then (ChartLib) ->
                $timeout ->
                    try
                        ctx = canvas.getContext('2d')
                        if !ctx
                            console.error("Failed to get canvas context")
                            isRendering = false
                            return
                        
                        destroyChart()
                        
                        # Area chart color (turquoise)
                        areaColor = data.color || '#44C2C2'
                        
                        # Chart.js configuration for area chart
                        config = {
                            type: 'line'
                            data: {
                                labels: data.labels
                                datasets: data.datasets.map (dataset) ->
                                    return {
                                        label: dataset.label || ''
                                        data: dataset.data
                                        borderColor: dataset.borderColor || areaColor
                                        backgroundColor: dataset.backgroundColor || (areaColor + '40')  # 25% opacity
                                        borderWidth: dataset.borderWidth || 2
                                        fill: false  # This creates the area effect
                                        tension: dataset.tension || 0.35  # Smooth curve
                                        pointRadius: dataset.pointRadius || 3
                                        pointHoverRadius: dataset.pointHoverRadius || 5
                                        pointBackgroundColor: dataset.pointBackgroundColor || areaColor
                                        pointBorderColor: dataset.pointBorderColor || '#ffffff'
                                        pointBorderWidth: dataset.pointBorderWidth || 1.5
                                        pointHoverBackgroundColor: dataset.pointHoverBackgroundColor || areaColor
                                        pointHoverBorderColor: dataset.pointHoverBorderColor || '#ffffff'
                                    }
                            }
                            options: {
                                responsive: true
                                maintainAspectRatio: false
                                scales: {
                                    x: {
                                        type: 'category'
                                        grid: {
                                            display: false
                                            drawBorder: true
                                            borderColor: '#cbd5e1'
                                        }
                                        ticks: {
                                            color: '#475569'
                                            font: {
                                                size: 11
                                            }
                                            maxRotation: 45
                                            minRotation: 45
                                        }
                                        title: {
                                            display: !!data.xAxisLabel
                                            text: data.xAxisLabel || ''
                                            color: '#1e293b'
                                            font: {
                                                size: 12
                                                weight: 600
                                            }
                                        }
                                    }
                                    y: {
                                        beginAtZero: true
                                        max: if data.yAxisMax? then data.yAxisMax else undefined
                                        grid: {
                                            display: true
                                            color: '#e2e8f0'
                                            drawBorder: true
                                            borderColor: '#cbd5e1'
                                        }
                                        ticks: {
                                            color: '#475569'
                                            font: {
                                                size: 11
                                            }
                                            stepSize: if data.yAxisStep? then data.yAxisStep else undefined
                                            callback: (value) ->
                                                return value unless typeof value is 'number'
                                                numericValue = Number(value)
                                                return value unless isFinite(numericValue)
                                                if data.isPercentage
                                                    return "#{numericValue.toFixed(1)}%"
                                                
                                                # If it's an integer, show as integer
                                                if Number.isInteger(numericValue)
                                                    return numericValue.toString()
                                                
                                                # Otherwise show with decimals
                                                numericValue.toFixed(2)
                                        }
                                        title: {
                                            display: !!data.yAxisLabel
                                            text: data.yAxisLabel || ''
                                            color: '#1e293b'
                                            font: {
                                                size: 12
                                                weight: 600
                                            }
                                        }
                                    }
                                }
                                plugins: {
                                    legend: {
                                        display: data.showLegend ? true
                                        position: 'top'
                                        align: 'start'
                                        labels: {
                                            color: '#1e293b'
                                            font: {
                                                size: 10
                                                weight: 500
                                            }
                                            usePointStyle: true
                                            pointStyle: 'circle'
                                            padding: 8
                                            boxWidth: 6
                                            boxHeight: 6
                                        }
                                    }
                                    title: {
                                        display: !!data.title
                                        text: data.title || ''
                                        color: '#1e293b'
                                        font: {
                                            size: 14
                                            weight: 600
                                        }
                                        padding: {
                                            top: 5
                                            bottom: 10
                                        }
                                    }
                                    tooltip: {
                                        mode: 'index'
                                        intersect: false
                                        backgroundColor: 'rgba(0, 0, 0, 0.8)'
                                        titleColor: '#fff'
                                        bodyColor: '#fff'
                                        borderColor: '#cbd5e1'
                                        borderWidth: 1
                                        padding: 10
                                        displayColors: true
                                        callbacks: {
                                            label: (context) ->
                                                label = context.dataset.label || ''
                                                value = context.parsed.y
                                                if value?
                                                    numericValue = Number(value)
                                                    if isFinite(numericValue)
                                                        formatted = if data.isPercentage then "#{numericValue.toFixed(2)}%" else numericValue.toFixed(3)
                                                        return "#{label}: #{formatted}".trim()
                                                return label
                                        }
                                    }
                                }
                            }
                        }
                        
                        chart = new ChartLib(ctx, config)
                        
                    catch error
                        console.error("Error creating area chart:", error)
                    finally
                        isRendering = false
                , 100
        
        scope.$watch 'data', (newVal, oldVal) ->
            if newVal
                renderChart(newVal)
            else
                destroyChart()
        , true
        
        scope.$on '$destroy', ->
            destroyChart()
    
    return {
        restrict: 'E'
        link: link
        scope: {
            data: '='
        }
    }

module.directive("tgAreaChart", ["$parse", "$timeout", AreaChartDirective])
