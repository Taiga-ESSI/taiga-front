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
    ($timeout, $translate) ->
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

            translations = {
                team: $translate.instant("METRICS.TEAM_METRICS_TITLE")
                project: $translate.instant("METRICS.PROJECT_METRICS_TITLE")
            }

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
                
                currentPath = window.location.pathname
                console.log("[MetricsMenu] Actualizando estado activo, path actual:", currentPath)
                
                # Determinar cuál debe estar activo
                isTeamActive = currentPath.includes("/metrics/team")
                isProjectActive = currentPath.includes("/metrics/project")
                
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
                
                # Observar cambios en la URL (para cuando se navega con botones del navegador)
                window.addEventListener "popstate", updateActiveState
                window.addEventListener "hashchange", updateActiveState
                
                # Usar $timeout para verificar periódicamente la URL y actualizar el estado
                # Esto maneja el caso de Angular routing
                checkInterval = null
                checkRouteChanges = ->
                    updateActiveState()
                    checkInterval = $timeout(checkRouteChanges, 500)
                
                checkRouteChanges()
                
                # Guardar el interval para limpiarlo después
                scope.checkInterval = checkInterval

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
                if scope.checkInterval
                    $timeout.cancel(scope.checkInterval)

        {
            restrict: "A"
            link: link
        }
]
