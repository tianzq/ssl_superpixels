function [img_cube,gt_cube] = load_samples_Xray(imgs_list,gts_list,samples_idx_struct)

% collect the patches of images and groundtruth

imgs_no = length(imgs_list);

% n_samples = size(samples_idx_struct.idxs,1);

p = samples_idx_struct.p;

ftrs_type = p.ftrs;


switch imgs_list{1}(end - 2:end)
    
    case 'dcm'
        
        img = load_PA_data(imgs_list{1});

        gt_img = load_PA_data(gts_list{1});

    case 'jpg'
    
        img = imread(imgs_list{1});

        gt_img = imread(gts_list{1});
        
        
    case 'tif'

        img = imread(imgs_list{1});
        
        gt_img = imread(gts_list{1});
        
    case 'ppm'
        
        img = imread(imgs_list{1});
        
        gt_img = imread(gts_list{1});
                
    otherwise
        
end
        

cube_size = samples_idx_struct.patch_size;

switch ftrs_type
    
    case 'Grayscale'
    
        img_cube = repmat(img(1),length(samples_idx_struct.idxs),prod(cube_size));
        
    case 'RGB'

        img_cube = repmat(img(1),length(samples_idx_struct.idxs),prod(cube_size) * 3);
        
        
    case 'Gabor'
        
        img_cube = repmat(img(1),length(samples_idx_struct.idxs),84);
        
        img_cube = double(img_cube);
        
    case 'Coye'
        
        img_cube = repmat(img(1),length(samples_idx_struct.idxs),9);
        
        img_cube = double(img_cube);
        
    otherwise
        
        img_cube = repmat(img(1),length(samples_idx_struct.idxs),prod(cube_size));
        
end


        
        
gt_cube =  repmat(gt_img(1),length(samples_idx_struct.idxs),prod(cube_size));

for i_img = 1 : imgs_no
        
    img_fn = imgs_list{i_img};
    
    img = imread(img_fn);
    
    img = img(:,:,1);
    
    
%     Adhoc_Retinal(img);
    
    
    
    gt_fn = gts_list{i_img};
    
    gt_img = imread(gt_fn);

    gt_img = gt_img > 0;
    
    
%     if(length(cube_size) == 2)
%        
%         img = img(:,:,2);
%         
%         gt_img = gt_img(:,:,1);
%         
%     end
    

    idx_img = samples_idx_struct.idxs(samples_idx_struct.img_idxs == i_img,:);
    
    n_ftrs = 1;
    
    switch ftrs_type
        
        case 'Grayscale'
            
            img_cube(samples_idx_struct.img_idxs == i_img,:) =...
                collect_patches(img,idx_img,cube_size);
            
        case 'RGB'
            
            for ib = 1 : size(img,3)
                
                tmp_img_cube = collect_patches(img(:,:,ib),idx_img,cube_size);
                
                n_ftrs_tmp = size(tmp_img_cube,2);
                
                img_cube(samples_idx_struct.img_idxs == i_img,n_ftrs : (n_ftrs + n_ftrs_tmp - 1)) = tmp_img_cube;
                
                n_ftrs = n_ftrs + n_ftrs_tmp;
                
            end
            
        case 'Gabor'
            
            features = Gabor_Filter(img);
       
            img_cube(samples_idx_struct.img_idxs == i_img,:) = features(idx_img,:);
            
       case 'Coye'     
           
           features = CoyeFilterXray(img);
           
           img_cube(samples_idx_struct.img_idxs == i_img,:) = collect_patches(features,idx_img,[3,3]);
           
        otherwise
            
    end
       
    gt_cube(samples_idx_struct.img_idxs == i_img,:) = collect_patches(gt_img,idx_img,cube_size);
    
end

end


function Z = CoyeFilterXray(img)
    
J = adapthisteq(img,'numTiles',[8 8],'nBins',128);

%% Background Exclusion
% Apply Average Filter
h = fspecial('average', [9 9]);
JF = imfilter(J, h);

% Take the difference between the gray image and Average Filter
Z = imsubtract(JF, J);

Z(Z > 0.1) = 0.1;

Z(Z < -0.1) = -0.1;

Z = (Z - mean2(Z)) / std2(Z);

end
