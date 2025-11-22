###
# This source code is licensed under the terms of the
# GNU Affero General Public License found in the LICENSE file in
# the root directory of this source tree.
#
# Copyright (c) 2021-present Kaleidos INC
###
###
# CREADOR POR: POL ALCOVERRO
# Descripción: Punto de entrada del módulo de métricas para inicializar dependencias y registros de Chart.js.
###

module = angular.module("taigaMetrics", ["taigaCustomization"])

# Ensure Chart.js components are registered when available (Chart.js v3+)
if window.Chart? and window.Chart.register? and window.Chart.registerables?
    unless window.Chart._taigaMetricsRegistered
        window.Chart.register.apply(window.Chart, window.Chart.registerables)
        window.Chart._taigaMetricsRegistered = true
