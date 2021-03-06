%% Linear Kalman Filter (LKF) Class
% *Author: Dylan Thomas*
%
% This class implements a linear Kalman filter from sample k=0 to sample
% k=kmax.
%
% *Note: the user must instantiate the class with no properties, as a
% structure with fieldnames matching all input properties, or all input
% properties separately.*

%% LKF Class Definition
classdef batch_LKF < batchFilter
% Inherits batchFilter abstract class
    
%% LKF Properties
% *Inputs:*
    properties
        
        nRK         % Scalar >= 5:
                    %
                    % The Runge Kutta iterations to perform for 
                    % coverting dynamics model from continuous-time 
                    % to discrete-time. Default value is 10 RK 
                    % iterations.
    end
    
%% LKF Methods
    methods
        % LKF constructor
        % Input order:
        % fmodel,hmodel,modelFlag,kInit,xhatInit,PInit,uhist,zhist,thist,Q,R,nRK
        function LKFobj = batch_LKF(varargin)
            % Prepare for superclass constructor
            if nargin == 0
                fprintf('Instantiating empty batch LKF class\n\n')
                super_args = {};
            elseif nargin == 1
                fprintf('Instantiating batch LKF class\n\n')
                super_args = varargin{1};
            elseif nargin < 11
                error('Not enough input arguments')
            else
                fprintf('Instantiating batch LKF class\n\n')
                super_args = cell(1,12);
                for jj = 1:12
                    super_args{jj} = varargin{jj};
                end
            end
            % batchFilter superclass constructor
            LKFobj@batchFilter(super_args{:});
            % Only do if intantiated class is not empty
            if nargin > 0
                % Extra argument checker method
                LKFobj = argumentsCheck(LKFobj);
            end
        end
        
        % This method checks the extra input arguments for LKF class
        function LKFobj = argumentsCheck(LKFobj)
            % Switch on number of extra arguments.
            switch length(LKFobj.optArgs)
                case 0
                    LKFobj.nRK = 10;
                case 1
                    LKFobj.nRK = LKFobj.optArgs{1};
                otherwise
                    error('Too many input arguments')
            end
            % Ensures extra input arguments have sensible values.
            if LKFobj.nRK < 5
                error('Number of Runge-Kutta iterations should be larger than 5')
            end
        end
        
        % This method initializes the LKF class filter
        function [LKFobj,xhatk,Pk,tk,vk] = initFilter(LKFobj)
            % Setup the output arrays
            LKFobj.xhathist     = zeros(LKFobj.nx,LKFobj.kmax+1);
            LKFobj.Phist        = zeros(LKFobj.nx,LKFobj.nx,LKFobj.kmax+1);
            LKFobj.eta_nuhist   = zeros(size(LKFobj.thist));
            
            % Initialize quantities for use in the main loop and store the 
            % first a posteriori estimate and its error covariance matrix.
            xhatk                                = LKFobj.xhatInit;
            Pk                                   = LKFobj.PInit;
            LKFobj.xhathist(:,LKFobj.kInit+1)    = LKFobj.xhatInit;
            LKFobj.Phist(:,:,LKFobj.kInit+1)     = LKFobj.PInit;
            vk                                   = zeros(LKFobj.nv,1);
            % Make sure correct initial tk is used.
            if LKFobj.kInit == 0
                tk = 0;
            else
                tk = LKFobj.thist(LKFobj.kInit);
            end
        end
        
        % This method performs LKF class filter estimation
        function LKFobj = doFilter(LKFobj)
            % Filter initialization method
            [LKFobj,xhatk,Pk,tk,vk] = initFilter(LKFobj);
            
            % Main filter loop.
            for k = LKFobj.kInit:(LKFobj.kmax-1)
                % Prepare loop
                kp1 = k+1;
                tkp1 = LKFobj.thist(kp1);
                uk = LKFobj.uhist(kp1,:)';
                
                % Perform dynamic propagation and measurement update
                [xbarkp1,Pbarkp1] = dynamicProp(LKFobj,xhatk,Pk,uk,vk,tk,tkp1,k);
                [xhatkp1,Pkp1,eta_nukp1] = measUpdate(LKFobj,xbarkp1,Pbarkp1,kp1);
                
                % Store results
                kp2 = kp1 + 1;
                LKFobj.xhathist(:,kp2) = xhatkp1;
                LKFobj.Phist(:,:,kp2) = Pkp1;
                LKFobj.eta_nuhist(kp1) = eta_nukp1;
                % Prepare for next sample
                xhatk = xhatkp1;
                Pk = Pkp1;
                tk = tkp1;
            end
        end
        
        % Dynamic propagation method, from sample k to sample k+1.
        function [xbarkp1,Pbarkp1] = dynamicProp(LKFobj,xhatk,Pk,uk,vk,tk,tkp1,k)
            % Check model types and get sample k a priori state estimate.
            if strcmp(LKFobj.modelFlag,'CD')
                [xbarkp1,F,Gamma] = c2dnonlinear(xhatk,uk,vk,tk,tkp1,LKFobj.nRK,LKFobj.fmodel,1);
            elseif strcmp(LKFobj.modelFlag,'DD')
                [xbarkp1,F,Gamma] = feval(LKFobj.fmodel,xhatk,uk,vk,k);
            else
                error('Incorrect flag for the dynamics-measurement models')
            end
            % Get sample k a priori error covariance
            Pbarkp1 = F*Pk*(F') + Gamma*LKFobj.Q*(Gamma');
        end
        
        % Measurement update method at sample k+1.
        function [xhatkp1,Pkp1,eta_nukp1] = measUpdate(LKFobj,xbarkp1,Pbarkp1,kp1)
            % Linearized at sample k+1 a priori state estimate.
            [zbarkp1,H] = feval(LKFobj.hmodel,xbarkp1,kp1,1);
            zkp1 = LKFobj.zhist(kp1,:)';
            % Innovations, innovation covariance, and filter gain.
            nukp1 = zkp1 - zbarkp1;
            Skp1 = H*Pbarkp1*(H') + LKFobj.R;
            Wkp1 = (Pbarkp1*(H'))/Skp1;
            % LMMSE sample k+1 a posteriori state estimate and covariance.
            xhatkp1 = xbarkp1 + Wkp1*nukp1;
            Pkp1 = Pbarkp1 - Wkp1*Skp1*(Wkp1');
            % Innovation statistics
            eta_nukp1 = nukp1'*(Skp1\nukp1);
        end
    end
end