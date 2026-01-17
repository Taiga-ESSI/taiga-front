###
# This source code is licensed under the terms of the
# GNU Affero General Public License found in the LICENSE file in
# the root directory of this source tree.
#
# Copyright (c) 2021-present Kaleidos
###

# Modificado, añadido por Pol Alcoverro
angular.module("taigaComponents").directive "tgMetricsMenu", [
    "$timeout",
    "$translate",
    "$rootScope",
    "$location",
    ($timeout, $translate, $rootScope, $location) ->
        link = (scope, element) ->
            navElement = null
            originalMetricsItem = null
            teamMetricsItem = null
            projectMetricsItem = null
            mutationObserver = null
            setupAttempts = 0
            maxSetupAttempts = 20
            locateAttempts = 0
            maxLocateAttempts = 10
            deregisterLocationListener = null

            translations = {
                team: $translate.instant("METRICS.TEAM_METRICS_TITLE")
                project: $translate.instant("METRICS.PROJECT_METRICS_TITLE")
            }

            # Inyecta los iconos SVG personalizados en el DOM si no existen
            injectCustomIcons = ->
                # Buscar si ya existe un sprite SVG en el documento
                existingSvg = document.querySelector('svg[style*="display: none"], svg.svg-sprite, svg#svg-sprite')
                
                # Si no hay sprite, buscar cualquier SVG oculto que contenga symbols
                if !existingSvg
                    allSvgs = document.querySelectorAll('svg')
                    for svg in allSvgs
                        if svg.querySelector('symbol')
                            existingSvg = svg
                            console.log("[MetricsMenu] Sprite encontrado con symbols:", svg)
                            break
                
                # Definir los nuevos símbolos
                teamMetricsSymbol = '<symbol id="icon-team-metrics" viewBox="0 0 400 400"><path class="path1" d="M140 180c33.1 0 60-26.9 60-60s-26.9-60-60-60-60 26.9-60 60 26.9 60 60 60zm0 20c-44.2 0-80 35.8-80 80v20c0 11 9 20 20 20h120c11 0 20-9 20-20v-20c0-44.2-35.8-80-80-80zm140-60c22.1 0 40-17.9 40-40s-17.9-40-40-40-40 17.9-40 40 17.9 40 40 40zm0 20c-25.8 0-48.4 14.9-59.6 36.5 6.6 5.6 12.5 12 17.3 19.1 10.7-5.6 23-9.6 36.3-9.6 33.1 0 60 26.9 60 60v14h26c11 0 20-9 20-20v-14c0-44.2-35.8-80-80-80z"/></symbol>'
                
                projectMetricsSymbol = '<symbol id="icon-project-metrics" viewBox="0 0 400 400"><path class="path1" d="M200 40C111.6 40 40 111.6 40 200c0 44.1 17.9 84.1 46.9 113.1l28.3-28.3C94.5 264.2 80 233.9 80 200c0-66.3 53.7-120 120-120s120 53.7 120 120c0 33.9-14.5 64.2-35.2 84.8l28.3 28.3C342.1 284.1 360 244.1 360 200C360 111.6 288.4 40 200 40z M200 160c-22.1 0-40 17.9-40 40s17.9 40 40 40 40-17.9 40-40S222.1 160 200 160z M228.3 171.7l64-64-28.3-28.3-64 64L228.3 171.7z"/></symbol>'
                
                if existingSvg
                    # Añadir los símbolos al sprite existente
                    if !document.getElementById('icon-team-metrics')
                        console.log("[MetricsMenu] Inyectando icon-team-metrics en sprite existente")
                        tempDiv = document.createElement('div')
                        tempDiv.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg">' + teamMetricsSymbol + '</svg>'
                        symbolElement = tempDiv.querySelector('symbol')
                        if symbolElement
                            existingSvg.appendChild(symbolElement)
                            console.log("[MetricsMenu] icon-team-metrics añadido:", document.getElementById('icon-team-metrics'))
                    
                    if !document.getElementById('icon-project-metrics')
                        console.log("[MetricsMenu] Inyectando icon-project-metrics en sprite existente")
                        tempDiv = document.createElement('div')
                        tempDiv.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg">' + projectMetricsSymbol + '</svg>'
                        symbolElement = tempDiv.querySelector('symbol')
                        if symbolElement
                            existingSvg.appendChild(symbolElement)
                            console.log("[MetricsMenu] icon-project-metrics añadido:", document.getElementById('icon-project-metrics'))
                else
                    # Crear un nuevo sprite SVG oculto
                    console.log("[MetricsMenu] Creando nuevo sprite SVG para iconos personalizados")
                    newSprite = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
                    newSprite.setAttribute('style', 'display: none; position: absolute; width: 0; height: 0;')
                    newSprite.setAttribute('id', 'metrics-icons-sprite')
                    newSprite.setAttribute('xmlns', 'http://www.w3.org/2000/svg')
                    
                    # Crear los symbols usando DOM API
                    tempDiv = document.createElement('div')
                    tempDiv.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg">' + teamMetricsSymbol + projectMetricsSymbol + '</svg>'
                    symbols = tempDiv.querySelectorAll('symbol')
                    for symbol in symbols
                        newSprite.appendChild(symbol)
                    
                    document.body.insertBefore(newSprite, document.body.firstChild)
                    console.log("[MetricsMenu] Nuevo sprite creado:", newSprite)
                
                # Verificar que los iconos existen
                console.log("[MetricsMenu] Verificación - icon-team-metrics existe:", !!document.getElementById('icon-team-metrics'))
                console.log("[MetricsMenu] Verificación - icon-project-metrics existe:", !!document.getElementById('icon-project-metrics'))

            # Extrae la URL base del enlace original
            extractBaseHref = (originalHref) ->
                if !originalHref
                    return ""
                # Eliminar /team o /project del final si existe
                baseHref = originalHref.replace(/\/(team|project)(\/)?$/, "")
                return baseHref

            # Actualiza el estado activo basado en la URL actual
            updateActiveState = ->
                return unless teamMetricsItem && projectMetricsItem
                
                currentPath = $location.path()
                console.log("[MetricsMenu] Actualizando estado activo, path actual:", currentPath)
                
                # Determinar cuál debe estar activo
                isTeamActive = currentPath.indexOf("/metrics/team") != -1
                isProjectActive = currentPath.indexOf("/metrics/project") != -1
                
                # Actualizar Team Metrics
                if isTeamActive
                    teamMetricsItem.classList.add("active")
                    teamMetricsItem.querySelector("a")?.classList.add("active")
                else
                    teamMetricsItem.classList.remove("active")
                    teamMetricsItem.querySelector("a")?.classList.remove("active")
                
                # Actualizar Project Metrics
                if isProjectActive
                    projectMetricsItem.classList.add("active")
                    projectMetricsItem.querySelector("a")?.classList.add("active")
                else
                    projectMetricsItem.classList.remove("active")
                    projectMetricsItem.querySelector("a")?.classList.remove("active")
                
                console.log("[MetricsMenu] Estado actualizado - Team active:", isTeamActive, "Project active:", isProjectActive)

            # Crea los dos elementos de menú separados
            createSeparateMenuItems = ->
                console.log("[MetricsMenu] createSeparateMenuItems llamado")
                return unless originalMetricsItem
                return if teamMetricsItem || projectMetricsItem # Ya creados

                # Inyectar iconos personalizados antes de usarlos
                injectCustomIcons()

                # Obtener el href original
                originalLink = originalMetricsItem.querySelector("a")
                console.log("[MetricsMenu] Link original:", originalLink)
                return unless originalLink
                
                originalHref = originalLink.getAttribute("href")
                console.log("[MetricsMenu] href original:", originalHref)
                baseHref = extractBaseHref(originalHref)
                console.log("[MetricsMenu] baseHref extraído:", baseHref)

                # Clonar el elemento original para mantener toda la estructura y estilos
                teamMetricsItem = originalMetricsItem.cloneNode(true)
                projectMetricsItem = originalMetricsItem.cloneNode(true)
                
                # Limpiar clases de estado activo en ambos clones
                teamMetricsItem.classList.remove("active", "active-dialog", "router-link-active")
                projectMetricsItem.classList.remove("active", "active-dialog", "router-link-active")
                
                # Actualizar el enlace y texto del item de Team
                teamLink = teamMetricsItem.querySelector("a")
                if teamLink
                    teamLink.setAttribute("href", "#{baseHref}/team")
                    teamLink.setAttribute("title", translations.team)
                    teamLink.classList.remove("active", "router-link-active")
                    teamLink.setAttribute("data-metrics-type", "team")
                    teamText = teamLink.querySelector(".menu-option-text")
                    if teamText
                        teamText.textContent = translations.team
                    # Reemplazar el SVG con icono inline para Team Metrics
                    teamSvg = teamLink.querySelector("svg")
                    if teamSvg
                        # Crear SVG inline con el icono de team metrics
                        teamSvg.innerHTML = '<path d="M140 180c33.1 0 60-26.9 60-60s-26.9-60-60-60-60 26.9-60 60 26.9 60 60 60zm0 20c-44.2 0-80 35.8-80 80v20c0 11 9 20 20 20h120c11 0 20-9 20-20v-20c0-44.2-35.8-80-80-80zm140-60c22.1 0 40-17.9 40-40s-17.9-40-40-40-40 17.9-40 40 17.9 40 40 40zm0 20c-25.8 0-48.4 14.9-59.6 36.5 6.6 5.6 12.5 12 17.3 19.1 10.7-5.6 23-9.6 36.3-9.6 33.1 0 60 26.9 60 60v14h26c11 0 20-9 20-20v-14c0-44.2-35.8-80-80-80z"/>'
                        teamSvg.setAttribute("viewBox", "0 0 400 400")
                        console.log("[MetricsMenu] Team SVG convertido a inline")
                
                # Actualizar el enlace y texto del item de Project
                projectLink = projectMetricsItem.querySelector("a")
                if projectLink
                    projectLink.setAttribute("href", "#{baseHref}/project")
                    projectLink.setAttribute("title", translations.project)
                    projectLink.classList.remove("active", "router-link-active")
                    projectLink.setAttribute("data-metrics-type", "project")
                    projectText = projectLink.querySelector(".menu-option-text")
                    if projectText
                        projectText.textContent = translations.project
                    # Reemplazar el SVG con icono inline para Project Metrics
                    projectSvg = projectLink.querySelector("svg")
                    if projectSvg
                        # Crear SVG inline con el icono de project metrics
                        projectSvg.innerHTML = '<path d="M200 40C111.6 40 40 111.6 40 200c0 44.1 17.9 84.1 46.9 113.1l28.3-28.3C94.5 264.2 80 233.9 80 200c0-66.3 53.7-120 120-120s120 53.7 120 120c0 33.9-14.5 64.2-35.2 84.8l28.3 28.3C342.1 284.1 360 244.1 360 200C360 111.6 288.4 40 200 40z M200 160c-22.1 0-40 17.9-40 40s17.9 40 40 40 40-17.9 40-40S222.1 160 200 160z M228.3 171.7l64-64-28.3-28.3-64 64L228.3 171.7z"/>'
                        projectSvg.setAttribute("viewBox", "0 0 400 400")
                        console.log("[MetricsMenu] Project SVG convertido a inline")
                
                # Agregar clases identificadoras
                teamMetricsItem.classList.add("metrics-team-item")
                projectMetricsItem.classList.add("metrics-project-item")
                teamMetricsItem.setAttribute("data-metrics-type", "team")
                projectMetricsItem.setAttribute("data-metrics-type", "project")
                
                console.log("[MetricsMenu] Nuevos items creados (clonados):", teamMetricsItem, projectMetricsItem)

                # Insertar los nuevos elementos antes del original
                parentList = originalMetricsItem.parentNode
                console.log("[MetricsMenu] Parent list:", parentList)
                parentList.insertBefore(teamMetricsItem, originalMetricsItem)
                parentList.insertBefore(projectMetricsItem, originalMetricsItem)
                console.log("[MetricsMenu] Nuevos items insertados")

                # Eliminar el elemento original
                originalMetricsItem.remove()
                console.log("[MetricsMenu] Item original eliminado. Proceso completado!")
                
                # Configurar el manejo de clases activas basado en la URL actual
                updateActiveState()
                
                # Agregar listeners a los enlaces para actualizar el estado al hacer click
                teamLink?.addEventListener "click", ->
                    $timeout(updateActiveState, 100)
                
                projectLink?.addEventListener "click", ->
                    $timeout(updateActiveState, 100)
                
                # Escuchar cambios de ruta desde Angular para evitar polling
                deregisterLocationListener = $rootScope.$on "$locationChangeSuccess", ->
                    $timeout(updateActiveState, 0)

                # También cubrir navegaciones del navegador
                window.addEventListener "popstate", updateActiveState
                window.addEventListener "hashchange", updateActiveState

            # Localiza el elemento de métricas original
            locateMetricsItem = ->
                locateAttempts++
                console.log("[MetricsMenu] Buscando elemento de métricas... (intento #{locateAttempts})")
                iconSelector = 'use[href="#icon-metrics"], use[xlink\\:href="#icon-metrics"], use[href="#icon-graph"], use[xlink\\:href="#icon-graph"]'
                icon = navElement?.querySelector(iconSelector)
                console.log("[MetricsMenu] Icono encontrado:", icon)
                originalMetricsItem = icon?.closest("li")
                console.log("[MetricsMenu] Item original encontrado:", originalMetricsItem)
                if originalMetricsItem
                    console.log("[MetricsMenu] Creando items separados...")
                    createSeparateMenuItems()
                else if locateAttempts < maxLocateAttempts
                    console.log("[MetricsMenu] No se encontró el elemento de métricas, reintentando...")
                    $timeout(locateMetricsItem, 200)
                else
                    console.error("[MetricsMenu] No se pudo encontrar el elemento de métricas después de #{maxLocateAttempts} intentos")

            setup = ->
                setupAttempts++
                console.log("[MetricsMenu] Iniciando setup... (intento #{setupAttempts})")
                console.log("[MetricsMenu] Element:", element)
                console.log("[MetricsMenu] Element[0]:", element[0])
                console.log("[MetricsMenu] Element[0] children:", element[0].children)
                
                # Buscar tg-project-navigation de diferentes maneras
                navElement = element[0].querySelector("tg-project-navigation")
                
                if !navElement
                    # Intentar buscar directamente en el elemento
                    navElement = element[0].getElementsByTagName("tg-project-navigation")[0]
                
                if !navElement
                    # Si element[0] es tg-legacy-loader, buscar dentro
                    loader = element[0].querySelector("tg-legacy-loader")
                    console.log("[MetricsMenu] Loader encontrado:", loader)
                    if loader
                        console.log("[MetricsMenu] Loader children:", loader.children)
                        navElement = loader.querySelector("tg-project-navigation") || loader.getElementsByTagName("tg-project-navigation")[0]
                        
                        # Si tiene shadow DOM, intentar acceder
                        if !navElement && loader.shadowRoot
                            console.log("[MetricsMenu] Buscando en shadowRoot del loader")
                            navElement = loader.shadowRoot.querySelector("tg-project-navigation")
                
                if !navElement && setupAttempts < maxSetupAttempts
                    console.log("[MetricsMenu] Nav element no encontrado, reintentando...")
                    $timeout(setup, 100)
                    return
                
                if !navElement
                    console.error("[MetricsMenu] No se pudo encontrar tg-project-navigation después de #{maxSetupAttempts} intentos")
                    return
                    
                console.log("[MetricsMenu] ✓ Nav element encontrado:", navElement)
                console.log("[MetricsMenu] Nav element tiene shadowRoot?", navElement.shadowRoot)
                
                # Si el navElement tiene shadow DOM, trabajar con él
                if navElement.shadowRoot
                    console.log("[MetricsMenu] Usando shadowRoot para buscar métricas")
                    navElement = navElement.shadowRoot
                
                # Esperar un poco más para que el DOM interno se renderice
                $timeout(locateMetricsItem, 300)

            setup()

            scope.$on "$destroy", ->
                # Limpieza si es necesaria
                mutationObserver?.disconnect()
                window.removeEventListener("popstate", updateActiveState)
                window.removeEventListener("hashchange", updateActiveState)
                deregisterLocationListener?()

        {
            restrict: "A"
            link: link
        }
]
