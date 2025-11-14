function [plateText, firstChar, recognizedState, imgWithBox] = detectLicensePlate_State(img)
    % Image Preprocessing 1: Convert to grayscale
    grayImg = rgb2gray(img);    

    % Image Preprocessing 2: Using a median filter to reduce noise
    denoisedImg = medfilt2(grayImg, [3, 3]); 

    % Image Preprocessing 3: Sharpening the image to make text clearer
    sharpenedImg = imsharpen(denoisedImg, 'Radius', 2, 'Amount', 1.5);

    % Image Preprocessing 4: histogram equalization
    contrastImg = adapthisteq(sharpenedImg, 'ClipLimit', 0.02); 

    % Image Preprocessing 5: Binary Thresholding: Convert the image to black and white 
    binaryImg = imbinarize(contrastImg, 'adaptive', 'Sensitivity', 0.5);
    
    % Image Segmentation: Morphological Opening - Erosion followed by dilation
    seOpen = strel('disk', 5);
    erodedImg = imerode(binaryImg, seOpen);
    openedImg = imdilate(erodedImg, seOpen);
    
    % Image Segmentation: Morphological Closing - Dilation followed by erosion
    seClose = strel('disk', 2);
    dilatedImg = imdilate(openedImg, seClose);
    cleanImg = imerode(dilatedImg, seClose);
    
    % Show figure for the steps
    figure('Position', [150, 120, 1000, 500]);
    t = tiledlayout(4, 3, 'Padding', 'compact', 'TileSpacing', 'compact');
    nexttile, imshow(img), title('Original Image');
    nexttile, imshow(grayImg), title('Grayscale');
    nexttile, imshow(denoisedImg), title('Denoised');
    nexttile, imshow(sharpenedImg), title('Sharpened');
    nexttile, imshow(contrastImg), title('Contrast Enhanced');
    nexttile, imshow(dilatedImg), title('Morphological Dilated');
    nexttile, imshow(cleanImg), title('Morphological Eroded');

    % Image Segmentation: Use Canny Edge to detect edges
    edges = edge(contrastImg, 'Canny');
    % Filling holes
    filledEdges = imfill(edges, 'holes');

    nexttile, imshow(edges), title('Canny Edge');
    nexttile, imshow(filledEdges), title('Filled Edge');

    % Label regions
    [labeledImg, ~] = bwlabel(filledEdges); 
    stats = regionprops(labeledImg, 'BoundingBox', 'Area');
    
    % Get index of largest region
    [~, idx] = max([stats.Area]); 
    % Get its bounding box
    boundingBox = stats(idx).BoundingBox; 
    % Segment and Crop the number plate
    croppedPlate = imcrop(img, boundingBox); 
    % Draw Red bounding box for number plate
    imgWithBox = insertShape(img, 'Rectangle', boundingBox, 'Color', 'red', 'LineWidth', 8);
    
    % Preprocess cropped plate for OCR
    plateGray = rgb2gray(croppedPlate);
    plateEnhanced = adapthisteq(plateGray);
    plateSharp = imsharpen(plateEnhanced);
    plateBinary = imbinarize(plateSharp);
    
    % Invert if background is dark
    if mean(plateBinary(:)) < 0.5
        plateBinary = imcomplement(plateBinary);
    end
    
    % Remove small noise
    % Morphological closing to fill broken characters 
    % [3,3] ideal for all success image
    plateBinary = imclose(plateBinary, strel('rectangle', [3, 3]));
    
    % OCR with restricted character set
    ocrResult = ocr(plateBinary, ...
        'CharacterSet', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', ...
        'TextLayout', 'Block');    
    % Clean result
    licensePlateNumber = regexprep(ocrResult.Text, '[^A-Z0-9]', '');

    % Get bounding boxes
    charBBoxes = ocrResult.CharacterBoundingBoxes;
    charTexts = ocrResult.Text;
    
    % Define state mappings
    stateMap = containers.Map(...
        {'A','B','C','D','F','J','K','M','N','P','R','T','W','V','Q','S','Z','H','I','U','4'}, ...
        {'Perak','Selangor','Pahang','Kelantan','Putrajaya','Johor','Kedah','Malacca', 'Negeri Sembilan',...
         'Penang','Perlis','Terengganu','Kuala Lumpur','Kuala Lumpur', 'Sarawak','Sabah',...
         'Military','Taxi','Special Series - IIUM','Special Series - UKM','Diplomatic Series'});
    
    % Get first character and corresponding state
    if ~isempty(licensePlateNumber)
        firstChar = licensePlateNumber(1);
        if isKey(stateMap, firstChar)
            stateName = stateMap(firstChar);
        else
            stateName = 'Unknown';
        end
    else
        firstChar = 'N/A';
        stateName = 'Unknown';
    end
    
    % Display first character and state
    disp(['First Character: ', firstChar]);
    disp(['State: ', stateName]);
    
    % Loop through recognized characters to find the first valid one
    for i = 1:length(charBBoxes)
        currentChar = upper(charTexts(i));  % Convert to uppercase
        if isstrprop(currentChar, 'alphanum') && currentChar == firstChar
            % Get character bounding box within cropped plate
            charBox = charBBoxes(i, :);
    
            % Transform box coordinates to original image by offsetting with car plate bbox
            adjustedCharBox = [charBox(1) + boundingBox(1), ...
                               charBox(2) + boundingBox(2), ...
                               charBox(3), charBox(4)];
            % Get the center of the bounding box
            centerX = adjustedCharBox(1) + adjustedCharBox(3) / 2;
            centerY = adjustedCharBox(2) + adjustedCharBox(4) / 2;            
            % Calculate base radius from bounding box size
            baseRadius = min(adjustedCharBox(3), adjustedCharBox(4)) / 2;
            
            % Scale the radius
            scaledRadius = baseRadius * 2; 
            
            % Draw yellow circle on the first character with red plate box
            imgWithBox = insertShape(imgWithBox, 'Circle', [centerX, centerY, scaledRadius], ...
                                     'Color', 'yellow', 'LineWidth', 4);
            break;
        end
    end

    % Display cropped plate and processed binary plate
    nexttile, imshow(croppedPlate), title('Cropped Plate');
    nexttile, imshow(plateBinary), title('Enhanced Plate for OCR');
    % Display license plate number, first character and state
    nexttile;
    text(0.1, 0.7, ['License Plate: ', licensePlateNumber], ...
         'FontSize', 12, 'FontWeight', 'bold', 'Color', 'blue', 'Units', 'normalized');
    text(0.1, 0.5, ['First Character: ', firstChar], ...
         'FontSize', 12, 'FontWeight', 'bold', 'Color', 'red', 'Units', 'normalized');
    text(0.1, 0.3, ['State: ', stateName], ...
         'FontSize', 12, 'FontWeight', 'bold', 'Color', '#77AC30', 'Units', 'normalized');
    axis off;

    plateText = licensePlateNumber;
    recognizedState = stateName;

    % Display final result with bounding box and circle
    figure('Name', 'Result of License Plate and State Detected', 'NumberTitle', 'off');
    imshow(imgWithBox);
    title('Result of License Plate and State Detected');

end

