function forest = Wilson_forestTrain( data, hs, udata, uhs, varargin )
% Train a semi supervised random forest classifier.
% The random forest approximates the information gain based on Wilson Score

%
% Dimensions:
%  M - number trees
%  F - number features
%  N - number input vectors
%  H - number classes
%
% USAGE
%  forest = forestTrain( data, hs, [varargin] )
%
% INPUTS
%  data     - [NxF] N length F feature vectors
%  hs       - [Nx1] or {Nx1} target output labels in [1,H]
%  varargin - additional params (struct or name/value pairs)
%   .M          - [1] number of trees to train
%   .H          - [max(hs)] number of classes
%   .N1         - [5*N/M] number of data points for training each tree
%   .F1         - [sqrt(F)] number features to sample for each node split
%   .split      - ['gini'] options include 'gini', 'entropy' and 'twoing'
%   .minCount   - [1] minimum number of data points to allow split
%   .minChild   - [1] minimum number of data points allowed at child nodes
%   .maxDepth   - [64] maximum depth of tree
%   .dWts       - [] weights used for sampling and weighing each data point
%   .fWts       - [] weights used for sampling features
%   .discretize - [] optional function mapping structured to class labels
%                    format: [hsClass,hBest] = discretize(hsStructured,H);
%
% OUTPUTS
%  forest   - learned forest model struct array w the following fields
%   .fids     - [Kx1] feature ids for each node
%   .thrs     - [Kx1] threshold corresponding to each fid
%   .child    - [Kx1] index of child for each node
%   .distr    - [KxH] prob distribution at each node
%   .hs       - [Kx1] or {Kx1} most likely label at each node
%   .count    - [Kx1] number of data points at each node
%   .depth    - [Kx1] depth of each node
%
% EXAMPLE
%  N=10000; H=5; d=2; [xs0,hs0,xs1,hs1]=demoGenData(N,N,H,d,1,1);
%  xs0=single(xs0); xs1=single(xs1);
%  pTrain={'maxDepth',50,'F1',2,'M',150,'minChild',5};
%  tic, forest=forestTrain(xs0,hs0,pTrain{:}); toc
%  hsPr0 = forestApply(xs0,forest);
%  hsPr1 = forestApply(xs1,forest);
%  e0=mean(hsPr0~=hs0); e1=mean(hsPr1~=hs1);
%  fprintf('errors trn=%f tst=%f\n',e0,e1); figure(1);
%  subplot(2,2,1); visualizeData(xs0,2,hs0);
%  subplot(2,2,2); visualizeData(xs0,2,hsPr0);
%  subplot(2,2,3); visualizeData(xs1,2,hs1);
%  subplot(2,2,4); visualizeData(xs1,2,hsPr1);
%
% See also forestApply, fernsClfTrain
%
% Piotr's Computer Vision Matlab Toolbox      Version 3.24
% Copyright 2014 Piotr Dollar.  [pdollar-at-gmail.com]
% Licensed under the Simplified BSD License [see external/bsd.txt]

% get additional parameters and fill in remaining parameters
dfs={ 'M',1, 'H',[], 'N1',[], 'F1',[], 'split','gini', 'minCount',1, ...
  'minChild',1, 'maxDepth',64, 'dWts',[], 'fWts',[], 'discretize','','SSL',1};
[M,H,N1,F1,splitStr,minCount,minChild,maxDepth,dWts,fWts,discretize,SSL] = ...
  getPrmDflt(varargin,dfs,1);
[N,F]=size(data); assert(length(hs)==N); discr=~isempty(discretize);
minChild=max(1,minChild); minCount=max([1 minCount minChild]);
if(isempty(H)), H=max(hs); end; assert(discr || all(hs>0 & hs<=H));
if(isempty(N1)), N1=round(5*N/M); end; N1=min(N,N1);
if(isempty(F1)), F1=round(sqrt(F)); end; F1=min(F,F1);
if(isempty(dWts)), dWts=ones(1,N,'single'); end; dWts=dWts/sum(dWts);
if(isempty(fWts)), fWts=ones(1,F,'single'); end; fWts=fWts/sum(fWts);
split=find(strcmpi(splitStr,{'gini','entropy','twoing'}))-1;
if(isempty(split)), error('unknown splitting criteria: %s',splitStr); end

% make sure data has correct types
if(~isa(data,'single')), data=single(data); end
if(~isa(hs,'uint32') && ~discr), hs=uint32(hs); end
if(~isa(udata,'single')), udata = single(udata); end
if(~isa(uhs,'uint32') && ~discr), uhs=uint32(uhs); end
if(~isa(fWts,'single')), fWts=single(fWts); end
if(~isa(dWts,'single')), dWts=single(dWts); end

% train M random trees on different subsets of data
prmTree = {H,F1,minCount,minChild,maxDepth,fWts,split,discretize,SSL};
for i=1:M
  if(N==N1), data1=data; hs1=hs; dWts1=dWts; udata1 = udata; uhs1 = uhs; else
    d=wswor(dWts,N1,4); data1=data(d,:); hs1=hs(d);
    dWts1=dWts(d); dWts1=dWts1/sum(dWts1); 
    
    N_udata = size(udata,1);
    
    N1_udata = round(5 * N_udata / M);
    
    N1_udata = min(N1_udata,size(udata,1));
    
    du = randi(N_udata,N1_udata,1);
    
    udata1 = udata(du,:);
    
    uhs1 = uhs(du);
    
    %udata1 = udata(d,:)
  end
  tree = treeTrain(data1,hs1,udata1,uhs1,dWts1,prmTree);
  if(i==1), forest=tree(ones(M,1)); else forest(i)=tree; end
end

end

function tree = treeTrain( data, hs, udata,uhs, dWts, prmTree )
% Train single random tree.
[H,F1,minCount,minChild,maxDepth,fWts,split,discretize,SSL]=deal(prmTree{:});
N=size(data,1); K=2*N-1; discr=~isempty(discretize);
thrs=zeros(K,1,'single'); distr=zeros(K,H,'single');
fids=zeros(K,1,'uint32'); child=fids; count=fids; depth=fids;

countu = count;

hsn=cell(K,1); dids=cell(K,1); dids{1}=uint32(1:N); k=1; K=2;

Nu = size(udata,1);

didus = cell(K,1);

didus{1} = uint32(1:Nu);

while( k < K )
  % get node data and store distribution
  dids1=dids{k}; dids{k}=[]; hs1=hs(dids1); n1=length(hs1); count(k)=n1;
  
  didus1 = didus{k}; didus{k}=[]; nu1 = size(didus1,1); countu(k) = nu1;
  
  
  if(discr), [hs1,hsn{k}]=feval(discretize,hs1,H); hs1=uint32(hs1); end
  if(discr), assert(all(hs1>0 & hs1<=H)); end; pure=all(hs1(1)==hs1);
  if(~discr), if(pure), distr(k,hs1(1))=1; hsn{k}=hs1(1); else
      distr(k,:)=histc(hs1,1:H)/n1; [~,hsn{k}]=max(distr(k,:)); end; end
  % if pure node or insufficient data don't train split
  if( pure || n1<=minCount || depth(k)>maxDepth ), k=k+1; continue; end
  % train split and continue
  fids1=wswor(fWts,F1,4); data1=data(dids1,fids1);
  [~,order1]=sort(data1); order1=uint32(order1-1);
  
  datau1 = udata(didus1,fids1);
  
  uhs1 = uhs(didus1);
  
  if(SSL)
      
     [fid,thr,gain] = WilsonSSLforestFindThr(data1,hs1,datau1,uhs1,dWts(dids1),order1,H,split);
      
  else
     
     [fid,thr,gain] = WilsonforestFindThr(data1,hs1,datau1,uhs1,dWts(dids1),order1,H,split);
      
  end
  
  fid=fids1(fid); left=data(dids1,fid)<thr; count0=nnz(left);
  
  leftu = udata(didus1,fid) < thr; 
  
  if( gain>1e-10 && count0>=minChild && (n1-count0)>=minChild )
    child(k)=K; fids(k)=fid-1; thrs(k)=thr;
    dids{K}=dids1(left); dids{K+1}=dids1(~left);
    
    didus{K} = didus1(leftu); didus{K + 1} = didus1(~leftu);
    
    depth(K:K+1)=depth(k)+1; K=K+2;
  end; k=k+1;
end
% create output model struct
K=1:K-1; if(discr), hsn={hsn(K)}; else hsn=[hsn{K}]'; end
tree=struct('fids',fids(K),'thrs',thrs(K),'child',child(K),...
  'distr',distr(K,:),'hs',hsn,'count',count(K),'depth',depth(K));
end

function ids = wswor( prob, N, trials )
% Fast weighted sample without replacement. Alternative to:
%  ids=datasample(1:length(prob),N,'weights',prob,'replace',false);
M=length(prob); assert(N<=M); if(N==M), ids=1:N; return; end
if(all(prob(1)==prob)), ids=randperm(M,N); return; end
cumprob=min([0 cumsum(prob)],1); assert(abs(cumprob(end)-1)<.01);
cumprob(end)=1; [~,ids]=histc(rand(N*trials,1),cumprob);
[s,ord]=sort(ids); K(ord)=[1; diff(s)]~=0; ids=ids(K);
if(length(ids)<N), ids=wswor(cumprob,N,trials*2); end
ids=ids(1:N)';
end

function [fid,thr,gain] = WilsonforestFindThr(data1,hs1,udata1,uhs1,dWts,order1,H,split)


Nl1 = sum(hs1 == 1);

Nl2 = sum(hs1 == 2);

g_gain = zeros(size(data1,2),1);

thr_c = zeros(size(data1,2),1);

order1 = order1 + 1;

for ifid = 1 : size(data1,2)
%   
%    d = data1(:,ifid); 
%     
%    d = d(order1(:,ifid));
   
   hs2 = hs1(order1(:,ifid));
   
   pdfl1 = hs2 == 1;
   
   pdfl2 = hs2 == 2;
   
   cdfl1 = cumsum(pdfl1);
   
   cdfl2 = cumsum(pdfl2);
   
   
   pl1 = (cdfl1 + 2) ./ (cdfl1 + cdfl2 + 4);

   pl2 = (cdfl2 + 2) ./ (cdfl1 + cdfl2 + 4);
   
   pr1 = (Nl1 - cdfl1 + 2) ./ (Nl1 + Nl2 - cdfl1 - cdfl2 + 4);
   
   pr2 = (Nl2 - cdfl2 + 2) ./ (Nl1 + Nl2 - cdfl1 - cdfl2 + 4);
   
%    
%    pl1 = (cdfl1) ./ (cdfl1 + cdfl2 + eps);
% 
%    pl2 = (cdfl2 ) ./ (cdfl1 + cdfl2 + eps);
%    
%    pr1 = (Nl1 - cdfl1 ) ./ (Nl1 + Nl2 - cdfl1 - cdfl2 + eps);
%    
%    pr2 = (Nl2 - cdfl2 ) ./ (Nl1 + Nl2 - cdfl1 - cdfl2 + eps);
   

   
   g_left = (cdfl1 + cdfl2) / (Nl1 + Nl2) .* (1 - pl1 .^ 2 - pl2 .^ 2);
   
   g_right = (Nl1 + Nl2 - cdfl1 - cdfl2) / (Nl1 + Nl2) .* (1 - pr1 .^ 2 - pr2 .^ 2);
   
   
   [g_gain(ifid),thr_idx] = min(g_left + g_right);
   
   thr_c(ifid) = data1(order1(thr_idx,ifid),ifid);
   
   
   %g_left = -cdfu .* (pl1 .* log(pl1) + pl2 .* log(pl2)) / N;
   
   %g_right = -(N - cdfu) .* (pr1 .* log(pr1) + pr2 .* log(pr2)) / N;
   
end


g_initial = 1 - (Nl1 / (Nl1 + Nl2)) ^ 2 - (Nl2 / (Nl1 + Nl2)) ^ 2;

g_gain = g_initial - g_gain;


[gain,fid] = max(g_gain);


thr = single(thr_c(fid));

end


function [fid,thr,gain] = WilsonSSLforestFindThr(data1,hs1,udata1,uhs1,dWts,order1,H,split)


Nl1 = sum(hs1 == 1);

Nl2 = sum(hs1 == 2);

g_gain = zeros(size(data1,2),1);

thr_c = zeros(size(data1,2),1);

order1 = order1 + 1;

N = size(udata1,1);

for ifid = 1 : size(data1,2)
%   
   d = data1(:,ifid); 
%     
   d = d(order1(:,ifid));
   
   hs2 = hs1(order1(:,ifid));
   
%    pdfl1 = hs2 == 1;
%    
%    pdfl2 = hs2 == 2;
%    

   
   %[d,~,dic] = unique(d);
   
   d = unique(d);
   
   pdfl1 = histc(data1(hs1 == 1,ifid),d);
   
   if(size(pdfl1,2) > 1)
      
       pdfl1 = pdfl1';
       
   end
   
   pdfl2 = histc(data1(hs1 == 2,ifid),d);
   
   if(size(pdfl2,2) > 1)
       
       pdfl2 = pdfl2';
       
   end
   
   cdfl1 = cumsum(pdfl1);
   
   cdfl2 = cumsum(pdfl2);
   
   
   pdu = histc(udata1(:,ifid),d);

   cdfu = cumsum(pdu);
   
%    cdfu2l = cdfu(dic);
   
   pl1 = (cdfl1 + 2) ./ (cdfl1 + cdfl2 + 4);

   pl2 = (cdfl2 + 2) ./ (cdfl1 + cdfl2 + 4);
   
   pr1 = (Nl1 - cdfl1 + 2) ./ (Nl1 + Nl2 - cdfl1 - cdfl2 + 4);
   
   pr2 = (Nl2 - cdfl2 + 2) ./ (Nl1 + Nl2 - cdfl1 - cdfl2 + 4);
   
%    
%    pl1 = (cdfl1) ./ (cdfl1 + cdfl2 + eps);
% 
%    pl2 = (cdfl2 ) ./ (cdfl1 + cdfl2 + eps);
%    
%    pr1 = (Nl1 - cdfl1 ) ./ (Nl1 + Nl2 - cdfl1 - cdfl2 + eps);
%    
%    pr2 = (Nl2 - cdfl2 ) ./ (Nl1 + Nl2 - cdfl1 - cdfl2 + eps);
   

   
   g_left = (cdfu) / (N) .* (1 - pl1 .^ 2 - pl2 .^ 2);
   
   g_right = (N - cdfu) / (N) .* (1 - pr1 .^ 2 - pr2 .^ 2);
   
   
   
   if(0)
       
       g_left_nssl = (cdfl1 + cdfl2) / (Nl1 + Nl2) .* (1 - pl1 .^ 2 - pl2 .^ 2);
       
       g_right_nssl = (Nl1 + Nl2 - cdfl1 - cdfl2) / (Nl1 + Nl2) .* (1 - pr1 .^ 2 - pr2 .^ 2);
       
       nl = length(cdfu);
       
       plot(1:nl,g_left + g_right,'r',1:nl,g_left_nssl + g_right_nssl,'g');
       
   end
   
   
   [g_gain(ifid),thr_idx] = min(g_left + g_right);
   
   thr_c(ifid) = d(thr_idx);
   
   
%    thr_c(ifid) = data1(order1(thr_idx,ifid),ifid);
   
   
   %g_left = -cdfu .* (pl1 .* log(pl1) + pl2 .* log(pl2)) / N;
   
   %g_right = -(N - cdfu) .* (pr1 .* log(pr1) + pr2 .* log(pr2)) / N;
   
end


g_initial = 1 - (Nl1 / (Nl1 + Nl2)) ^ 2 - (Nl2 / (Nl1 + Nl2)) ^ 2;

g_gain = g_initial - g_gain;


[gain,fid] = max(g_gain);


thr = single(thr_c(fid));

end