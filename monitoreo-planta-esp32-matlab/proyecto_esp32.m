%% COMPARACIÓN SIN DEEP LEARNING TOOLBOX: PRUEBA LOCAL (prueba_cam.jpg.jpg) Y ESP32
% No requiere Deep Learning Toolbox ni paquetes adicionales.

clear; clc; close all;

%% --- 1. CONFIGURACIÓN ---
modoPruebaLocal = true;                 % true = usa rutaPruebaCam | false = usa urlCamara
urlCamara       = 'http://10.5.36.180'; % URL del ESP32 cuando esté listo
rutaReferencia  = 'planta_ref.jpg.png'; % Imagen de referencia en C:\Users\USUARIO\Documents
rutaPruebaCam   = 'prueba_cam.jpg.jpg'; % Imagen de prueba local en C:\Users\USUARIO\Documents
sz              = [128 128];            % Tamaño estándar para comparar
umbralSimilitud = 0.75;                 % Ajusta según el puntaje que veas (0.0 a 1.0)
intervaloSeg    = 0.50;                 % Pausa entre lecturas (segundos)

%% --- 2. VERIFICAR ARCHIVOS Y EXTRAER VECTOR DE REFERENCIA ---
if ~exist(rutaReferencia, 'file')
    error('No se encontró "%s" en la carpeta actual (%s).', rutaReferencia, pwd);
end

if modoPruebaLocal && ~exist(rutaPruebaCam, 'file')
    error('No se encontró "%s" en la carpeta actual (%s).', rutaPruebaCam, pwd);
end

imgRef = imread(rutaReferencia);
f1 = extraerVectorComparacion(imgRef, sz);
fprintf('Referencia "%s" cargada y lista.\n', rutaReferencia);

%% --- 3. VENTANA DE VISUALIZACIÓN Y BUCLE DE COMPARACIÓN ---
fig = figure('Name', 'Comparación Planta (Sin ResNet-18)', 'NumberTitle', 'off');

subplot(1, 2, 1);
imshow(imgRef);
title('Referencia (Planta)', 'Interpreter', 'none');

axCam = subplot(1, 2, 2);
imshow(zeros(240, 320, 3, 'uint8'), 'Parent', axCam);
title('Esperando imagen...', 'Color', [0.3 0.3 0.3]);

while ishandle(fig)
    if modoPruebaLocal
        imgCam = imread(rutaPruebaCam);
    else
        imgCam = obtenerFrameCamara(urlCamara);
    end

    if ~isempty(imgCam)
        f2 = extraerVectorComparacion(imgCam, sz);

        % Similitud del coseno entre vectores normalizados (0.0 a 1.0 aprox.)
        similitud = max(0, min(1, dot(f1, f2)));
        coincide  = similitud >= umbralSimilitud;

        imshow(imgCam, 'Parent', axCam);
        if coincide
            estado = 'COINCIDE';
            colorTxt = [0.0 0.55 0.0];
        else
            estado = 'NO COINCIDE';
            colorTxt = [0.85 0.0 0.0];
        end

        title(axCam, sprintf('%s  |  Similitud: %.3f', estado, similitud), ...
            'Color', colorTxt, 'FontWeight', 'bold');
        drawnow limitrate;
    end

    pause(intervaloSeg);
end

%% --- 4. VECTOR DE COMPARACIÓN SIN DEEP LEARNING ---
function vec = extraerVectorComparacion(img, sz)
    % Convierte a RGB si viene en escala de grises y redimensiona
    if size(img, 3) == 1
        img = repmat(img, [1 1 3]);
    elseif size(img, 3) > 3
        img = img(:, :, 1:3);
    end

    imgRes = im2double(imresize(img, sz));

    % Combina intensidad/estructura redimensionada (peso 0.7) e histograma RGB (peso 0.3)
    vecImg = imgRes(:)';
    vecImg = vecImg / (norm(vecImg) + eps);

    nBins = 16;
    edges = linspace(0, 1, nBins + 1);
    hR = histcounts(imgRes(:, :, 1), edges, 'Normalization', 'probability');
    hG = histcounts(imgRes(:, :, 2), edges, 'Normalization', 'probability');
    hB = histcounts(imgRes(:, :, 3), edges, 'Normalization', 'probability');
    vecHist = [hR, hG, hB];
    vecHist = vecHist / (norm(vecHist) + eps);

    vec = [0.7 * vecImg, 0.3 * vecHist];
    vec = vec / (norm(vec) + eps);
end

%% --- 5. FUNCIÓN AUXILIAR PARA OBTENER FRAME (JPEG DIRECTO O MJPEG STREAM) ---
function img = obtenerFrameCamara(url)
    img = [];
    try
        opts = weboptions('Timeout', 5, 'ContentType', 'raw');
        raw = webread(url, opts);

        if ischar(raw) || isstring(raw)
            raw = uint8(raw);
        end

        if isempty(raw) || ~isa(raw, 'uint8')
            return;
        end

        raw = raw(:)';

        idxInicio = strfind(raw, uint8([255, 216]));
        idxFin    = strfind(raw, uint8([255, 217]));

        if ~isempty(idxInicio) && ~isempty(idxFin)
            inicio = idxInicio(1);
            finCandidates = idxFin(idxFin > inicio);
            if ~isempty(finCandidates)
                fin = finCandidates(1) + 1;
                jpegBytes = raw(inicio:fin);
                img = imdecode(jpegBytes, 'jpeg');
                return;
            end
        end

        img = imdecode(raw, 'jpeg');

    catch ME
        warning('ESP32Cam:Lectura', 'Sin frame disponible (%s)', ME.message);
    end
end