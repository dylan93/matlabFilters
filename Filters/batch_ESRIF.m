%% Extended Square-Root Information Filter (ESRIF) Class
% *Author: Dylan Thomas*
%
% This class implements an extended square-root information filter from
% sample k=0 to sample k=kmax.
%

%% TODO:
%
% # Demystify beginning sample/tk = 0 problem (kinit maybe?)
% # Get rid of inv( ) warnings
% # Add continuous measurement model functionality?

%% ESRIF Class Deinfition
classdef batch_ESRIF < batchFilter
% Inherits batchFilter abstract class

%% ESRIF Properties
% *Inputs:*
    properties 

        nRK         % scalar:
                    %
                    % The Runge Kutta iterations to perform for 
                    % coverting dynamics model from continuous-time 
                    % to discrete-time. Default value is 20 RK 
                    % iterations.
    end

%%%
% *Derived Properties:*
    properties
                
        Rvvk        % (nv)x(nv) matrix:
                    % 
                    % The square-root information process noise 
                    % covariance.
                    
        Rxxk        % (nx)x(nx) matrix:
                    %
                    % The square-root information state error a 
                    % posteriori covariance matrix at sample k.
        
        Ra          % (nz)x(nz) matrix:
                    % 
                    % The transformation matrix to ensure that the
                    % measurement noise is zero mean with identity
                    % covariance.
        
        Rainvtr     % (nz)x(nz) matrix:
                    % 
                    % Ra inversed and transposed - for convenience.
        
        zahist      % (kmax)x(nz) array:
                    %
                    % The transformed measurement state time-history 
                    % which ensures zero mean, identity covariance 
                    % noise.
    end
    
%% ESRIF Methods
    methods
        % ESRIF constructor
        function ESRIFobj = batch_ESRIF(fmodel,hmodel,modelFlag,xhat0,P0,uhist,zhist,thist,Q,R,varargin)
            % Prepare for superclass constructor
            if nargin == 0
                super_args = cell(1,11);
            elseif nargin < 10
                error('Not enough input arguments')
            else
                super_args{1}   = fmodel;
                super_args{2}   = hmodel;
                super_args{3}   = modelFlag;
                super_args{4}   = xhat0;
                super_args{5}   = P0;
                super_args{6}   = uhist;
                super_args{7}   = zhist;
                super_args{8}   = thist;
                super_args{9}   = Q;
                super_args{10}  = R;
                super_args{11}  = varargin;
            end
            % batchFilter superclass constructor
            ESRIFobj@batchFilter(super_args{:});
            % Extra argument checker method
            ESRIFobj = argumentsCheck(ESRIFobj);
        end
        
        % This method checks the extra input arguments for ESRIF class
        function ESRIFobj = argumentsCheck(ESRIFobj)
            % Switch on number of extra arguments.
            switch length(ESRIFobj.optArgs)
                case 0
                    ESRIFobj.nRK = 20;
                case 1
                    ESRIFobj.nRK = ESRIFobj.optArgs{1};
                otherwise
                    error('Not enough input arguments')
            end
            % Ensures extra input arguments have sensible values.
            if ESRIFobj.nRK < 5
                error('Number of Runge-Kutta iterations should be larger than 5')
            end
        end
        
        % This method initializes the ESRIF class filter
        function [ESRIFobj,xhatk,Pk,tk,vk] = initFilter(ESRIFobj)
            % Setup the output arrays
            ESRIFobj.xhathist     = zeros(ESRIFobj.nx,ESRIFobj.kmax+1);
            ESRIFobj.Phist        = zeros(ESRIFobj.nx,ESRIFobj.nx,ESRIFobj.kmax+1);
            ESRIFobj.eta_nuhist   = zeros(size(ESRIFobj.thist));
            
            % Initialize quantities for use in the main loop and store the 
            % first a posteriori estimate and its error covariance matrix.
            xhatk                   = ESRIFobj.xhat0;
            Pk                      = ESRIFobj.P0;
            ESRIFobj.xhathist(:,1)    = ESRIFobj.xhat0;
            ESRIFobj.Phist(:,:,1)     = ESRIFobj.P0;
            tk                      = 0;
            vk                      = zeros(ESRIFobj.nv,1);
        end
        
        % This method performs ESRIF class filter estimation
        function ESRIFobj = doFilter(ESRIFobj)
            % Filter initialization method
            [ESRIFobj,xhatk,~,tk,vk] = initFilter(ESRIFobj);
            
            % Determine the square-root information matrix for the process 
            % noise, and transform the measurements to have an error with 
            % an identity covariance.
            ESRIFobj.Rvvk = inv(chol(ESRIFobj.Q)');
            ESRIFobj.Ra = chol(ESRIFobj.R);
            ESRIFobj.Rainvtr = inv(ESRIFobj.Ra');
            ESRIFobj.zahist = ESRIFobj.zhist*(ESRIFobj.Rainvtr');
            
            % Initialize quantities for use in the main loop and store the 
            % first a posteriori estimate and its error covariance matrix.
            ESRIFobj.Rxxk = inv(chol(ESRIFobj.P0)');
            
            % Main filter loop.
            for k = 0:(ESRIFobj.kmax-1)
                % Prepare loop
                kp1 = k+1;
                tkp1 = ESRIFobj.thist(kp1);
                
                % Perform dynamic propagation and measurement update
                [xbarkp1,zetabarxkp1,Rbarxxkp1] = ...
                    dynamicProp(ESRIFobj,xhatk,vk,tk,tkp1,k);
                [zetaxkp1,Rxxkp1,zetarkp1] = ...
                    measUpdate(ESRIFobj,xbarkp1,zetabarxkp1,Rbarxxkp1,kp1);
                
                % Compute the state estimate and covariance at sample k + 1
                Rxxkp1inv = inv(Rxxkp1);
                xhatkp1 = Rxxkp1\zetaxkp1;
                Pkp1 = Rxxkp1inv*(Rxxkp1inv');
                % Store results
                kp2 = kp1 + 1;
                ESRIFobj.xhathist(:,kp2) = xhatkp1;
                ESRIFobj.Phist(:,:,kp2) = Pkp1;
                ESRIFobj.eta_nuhist(kp1) = zetarkp1'*zetarkp1;
                % Prepare for next sample
                ESRIFobj.Rxxk = Rxxkp1;
                xhatk = xhatkp1;
                tk = tkp1;

            end
        end
        
        % Dynamic propagation method, from sample k to sample k+1.
        function [xbarkp1,zetabarxkp1,Rbarxxkp1] = dynamicProp(ESRIFobj,xhatk,vk,tk,tkp1,k)
            % Check model types and get sample k a priori state estimate.
            if strcmp(ESRIFobj.modelFlag,'CD')
                [xbarkp1,F,Gamma] = c2dnonlinear(xhatk,ESRIFobj.uhist(k+1,:)',vk,tk,tkp1,ESRIFobj.nRK,ESRIFobj.fmodel,1);
            elseif strcmp(ESRIFobj.modelFlag,'DD')
                [xbarkp1,F,Gamma] = feval(ESRIFobj.fmodel,xhatk,ESRIFobj.uhist(k+1,:)',vk,k);
            else
                error('Incorrect flag for the dynamics-measurement models')
            end
            Finv = inv(F);
            FinvGamma = F\Gamma;
            % QR Factorize
            Rbig = [ESRIFobj.Rvvk,      zeros(ESRIFobj.nv,ESRIFobj.nx); ...
                  (-ESRIFobj.Rxxk*FinvGamma),         ESRIFobj.Rxxk/F];
            [Taktr,Rdum] = qr(Rbig);
            Tak = Taktr';
            zdum = Tak*[zeros(ESRIFobj.nv,1);ESRIFobj.Rxxk*Finv*xbarkp1];
            % Retrieve SRIF terms at k+1 sample
            idumxvec = [(ESRIFobj.nv+1):(ESRIFobj.nv+ESRIFobj.nx)]';
            Rbarxxkp1 = Rdum(idumxvec,idumxvec);
            zetabarxkp1 = zdum(idumxvec,1);
        end
        
        % Measurement update method at sample k+1.
        function [zetaxkp1,Rxxkp1,zetarkp1] = measUpdate(ESRIFobj,xbarkp1,zetabarxkp1,Rbarxxkp1,kp1)
            % Linearized at sample k+1 a priori state estimate.
            [zbarkp1,H] = feval(ESRIFobj.hmodel,xbarkp1,1);
            % Transform ith H(k) matrix and non-homogeneous measurement terms
            Ha = ESRIFobj.Rainvtr*H;
            zEKF = ESRIFobj.zahist(kp1,:)' - ESRIFobj.Rainvtr*zbarkp1 + Ha*xbarkp1;
            % QR Factorize
            [Tbkp1tr,Rdum] = qr([Rbarxxkp1;Ha]);
            Tbkp1 = Tbkp1tr';
            zdum = Tbkp1*[zetabarxkp1;zEKF];
            % Retrieve k+1 SRIF terms
            idumxvec = [1:ESRIFobj.nx]';
            Rxxkp1 = Rdum(idumxvec,idumxvec);
            zetaxkp1 = zdum(idumxvec,1);
            zetarkp1 = zdum(ESRIFobj.nx+1:end);
        end
    end
end