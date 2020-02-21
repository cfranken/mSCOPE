%% mSCOPE.m (script)

%     The model mSCOPE is based upon the SCOPE model. It simulates the
%     light interaction and energy balance of vertically heterogeneous canopies.
%     mSCOPE keeps the same structure, output of SCOPE, but it uses a
%     different solution for the radiative transfer in vegetation canopies
%     For the use of mSCOPE, please contact
%     p.yang@utwente.nl (Peiqi Yang)
% 
%     SCOPE is a coupled radiative transfer and energy balance model
%     Copyright (C) 2015  Christiaan van der Tol
%
%     This program is free software: you can redistribute it and/or modify
%     it under the terms of the GNU General Public License as published by
%     the Free Software Foundation, either version 3 of the License, or
%     any later version.
%
%     This program is distributed in the hope that it will be useful,
%     but WITHOUT ANY WARRANTY; without even the implied warranty of
%     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%     GNU General Public License for more details.
%
%     You should have received a copy of the GNU General Public License
%     along with this program.  If not, see <http://www.gnu.org/licenses/>.
%%
addpath RTMs
addpath Supporting
addpath Fluxes
addpath IO

%% 0. globals
global constants

%% 1. define constants
[constants] = define_constants(); % supporting, such as planck constant, speed of ligh, Stefan Boltzman constant

%% 2. simulation options
path_of_code        = cd;
parameter_file      = {'input_data.xlsx'};  % USE XLSX file for cross-platform compatibility
options             = readStructFromExcel(char(parameter_file), 'options', 3, 1);

if options.simulation>2 || options.simulation<0, fprintf('\n simulation option should be between 0 and 2 \r'); return, end

%% 3. file names
[dummy,X]                       = xlsread(char(parameter_file),'filenames');
j = find(~strcmp(X(:,2),{''}));
X = X(j,(1:end));
F = struct('FileID',{'Simulation_Name','soil_file','leaf_file','atmos_file'...
    'Dataset_dir','t_file','year_file','Rin_file','Rli_file'...
    ,'p_file','Ta_file','ea_file','u_file','CO2_file','z_file','tts_file'...
    ,'LAI_file','hc_file','SMC_file','Vcmax_file','Cab_file'});
for i = 1:length(F)
    k = find(strcmp(F(i).FileID,strtok(X(:,1))));
    if ~isempty(k)
        F(i).FileName = strtok(X(k,2));
        %if i==4, F(i).FileName = strtok(X(k,2:end)); end
    end
end
%% 4. input data

[N,X]                       = xlsread(char(parameter_file),'inputdata', '');
X                           = X(9:end,1);
V                           = assignvarnames;
mly                         = input_mSCOPE(parameter_file);

options.Cca_function_of_Cab = 0;

for i = 1:length(V)
    j = find(strcmp(strtok(X(:,1)),V(i).Name));
    if isempty(j) || sum(~isnan(N(j,:)))<1
        if i==2
            fprintf(1,'%s %s %s \n','warning: input "', V(i).Name, '" not provided in input spreadsheet...');
            fprintf(1,'%s %s %s\n', 'I will use 0.25*Cab instead');
            options.Cca_function_of_Cab = 1;
        else
            
            if ~(options.simulation==1) && (i==30 || i==32)
                fprintf(1,'%s %s %s \n','warning: input "', V(i).Name, '" not provided in input spreadsheet...');
                fprintf(1,'%s %s %s\n', 'I will use the MODTRAN spectrum "',char(F(4).FileName(1)),'" as it is');
            else
                if (options.simulation == 1 || (options.simulation~=1 && (i<46 || i>50)))
                    fprintf(1,'%s %s %s \n','warning: input "', V(i).Name, '" not provided in input spreadsheet');
                    if (options.simulation ==1 && (i==1 ||i==9||i==22||i==23||i==54 || (i>29 && i<37)))
                        fprintf(1,'%s %s %s\n', 'I will look for the values in Dataset Directory "',char(F(5).FileName),'"');
                    else
                        if (i== 24 || i==25)
                            fprintf(1,'%s %s %s\n', 'will estimate it from LAI, CR, CD1, Psicor, and CSSOIL');
                            options.calc_zo = 1;
                        else
                            if (i>38 && i<44)
                                fprintf(1,'%s %s %s\n', 'will use the provided zo and d');
                                options.calc_zo = 0;
                            else
                                if ~(options.simulation ==1 && (i==30 ||i==32))
                                    fprintf(1,'%s \n', 'this input is required: SCOPE ends');
                                    return
                                else
                                    fprintf(1,'%s %s %s\n', '... no problem, I will find it in Dataset Directory "',char(F(5).FileName), '"');
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    if sum(~isnan(N(j,:)))<1
        V(i).Val            = -999;
    else
        V(i).Val            = N(j,~isnan(N(j,:)));
    end
end

%% 5. Declare paths
path_input      = '../inputdata/input/';          % path of all inputs

%% 6. Numerical parameters (iteration stops etc)
iter.maxit           = 300;                          %                   maximum number of iterations
iter.maxEBer         = 1;                            %[W m-2]            maximum accepted error in energy bal.
iter.Wc              = 1;                         %                   Weight coefficient for iterative calculation of Tc

%% 7. Load spectral data for leaf and soil
opticoef    = load([path_input,'fluspect_parameters/',char(F(3).FileName)]);  % file with leaf spectral parameters
rsfile      = load([path_input,'soil_spectrum/',char(F(2).FileName)]);        % file with soil reflectance spectra

% Optical coefficient data used by fluspect
optipar.nr    = opticoef(:,2);
optipar.Kab   = opticoef(:,3);
optipar.Kca   = opticoef(:,4);
optipar.Ks    = opticoef(:,5);
optipar.Kw    = opticoef(:,6);
optipar.Kdm   = opticoef(:,7);
optipar.phiI  = opticoef(:,9);
optipar.phiII = opticoef(:,10);
%optipar.GSV1  = opticoef(:,11); soil spectra, not used yet
%optipar.GSV2  = opticoef(:,12);
%optipar.GSV3  = opticoef(:,13);

%% 8. Load directional data from a file
if options.calc_directional
    anglesfile          = load([path_input,'directional/brdf_angles2.dat']); %     Multiple observation angles in case of BRDF calculation
    directional.tto     = anglesfile(:,1);              % [deg]             Observation zenith Angles for calcbrdf
    directional.psi     = anglesfile(:,2);              % [deg]             Observation zenith Angles for calcbrdf
    directional.noa     = length(directional.tto);      %                   Number of Observation Angles
end

%% 9. Define canopy structure
canopy.nlayers  = 60;
nl              = canopy.nlayers;
canopy.x        = (-1/nl : -1/nl : -1)';         % a column vector
canopy.xl       = [0; canopy.x];                 % add top level
canopy.nlincl   = 13;
canopy.nlazi    = 36;
canopy.litab    = [ 5:10:75 81:2:89 ]';   % a column, never change the angles unless 'ladgen' is also adapted
canopy.lazitab  = ( 5:10:355 );           % a row

%% 10. Define spectral regions
[spectral] = define_bands;

wlS  = spectral.wlS;    % SCOPE 1.40 definition
wlP  = spectral.wlP;    % PROSPECT (fluspect) range
wlT  = spectral.wlT;    % Thermal range
wlF  = spectral.wlF;    % Fluorescence range

I01  = find(wlS<min(wlF));   % zero-fill ranges for fluorescence
I02  = find(wlS>max(wlF));
N01  = length(I01);
N02  = length(I02);

nwlP = length(wlP);
nwlT = length(wlT);

nwlS = length(wlS);

spectral.IwlP = 1 : nwlP;
spectral.IwlT = nwlP+1 : nwlP+nwlT;
spectral.IwlF = (640:850)-399;

[rho,tau] = deal(zeros(60,nwlP + nwlT));
[rs] = deal(zeros(nwlP + nwlT,1));

%% 11. load time series data
if options.simulation == 1
    vi = ones(length(V),1);
    [soil,leafbio,canopy,meteo,angles,xyt]  = select_input(V,vi,canopy,options);
    % canopy and leafbio from the profile data. overrule the orginal input
    canopy.LAI      =   mly.totLAI; 
    leafbio.Cab     =   mly.mCab;
    leafbio.Cca     =   mly.mCca;
    leafbio.Cdm     =   mly.mCdm;
    leafbio.Cw      =   mly.mCw;
    leafbio.Cs      =   mly.mCs;
    leafbio.N       =   mly.mN;
    [V,xyt,canopy]  = load_timeseries(V,leafbio,soil,canopy,meteo,constants,F,xyt,path_input,options);
else
    soil = struct;
end

%% 12. preparations
if options.simulation==1
    diff_tmin           =   abs(xyt.t-xyt.startDOY);
    diff_tmax           =   abs(xyt.t-xyt.endDOY);
    I_tmin              =   find(min(diff_tmin)==diff_tmin);
    I_tmax              =   find(min(diff_tmax)==diff_tmax);
    if options.soil_heat_method<2
        if (isempty(meteo.Ta) || meteo.Ta<-273), meteo.Ta = 20; end
        soil.Tsold = meteo.Ta*ones(12,2);
    end
end

nvars = length(V);
vmax = ones(nvars,1);
for i = 1:nvars
    vmax(i) = length(V(i).Val);
end
vmax([14,27],1) = 1; % these are Tparam and LADFb
vi      = ones(nvars,1);
switch options.simulation
    case 0, telmax = max(vmax);  [xyt.t,xyt.year]= deal(zeros(telmax,1));
    case 1, telmax = size(xyt.t,1);
    case 2, telmax  = prod(double(vmax)); [xyt.t,xyt.year]= deal(zeros(telmax,1));
end
[rad,thermal,fluxes] = initialize_output_structures(spectral);
atmfile     = [path_input 'radiationdata/' char(F(4).FileName(1))];
atmo.M      = aggreg(atmfile,spectral.SCOPEspec);

%% 13. create output files
create_output_files

%% 14. Run the model
fprintf('\n The calculations start now \r')
calculate = 1;

for k = 1:telmax
    
    if options.simulation == 1, vi(vmax>1) = k; end
    if options.simulation == 0, vi(vmax==telmax) = k; end
    [soil,leafbio,canopy,meteo,angles,xyt] = select_input(V,vi,canopy,options,xyt,soil);
    if options.simulation ~=1
        fprintf('simulation %i ', k );
        fprintf('of %i \n', telmax);
    else
        calculate = 0;
        if k>=I_tmin && k<=I_tmax
            quality_is_ok   = ~isnan(meteo.p*meteo.Ta*meteo.ea*meteo.u.*meteo.Rin.*meteo.Rli);
            fprintf('time = %4.2f \n', xyt.t(k));
            if quality_is_ok
                calculate = 1;
            end
        end
    end
    
    if calculate
        
        iter.counter = 0;
        canopy.lidf  = leafangles(canopy.LIDFa,canopy.LIDFb);    % This is 'ladgen' in the original SAIL model,
        
        fversion = @fluspect_bcar;
        [leafopt]= fluspect_mSCOPE(mly,spectral,leafbio,optipar);    
        
        IwlP     = spectral.IwlP;
        IwlT     = spectral.IwlT;
        rho(1:60,IwlP)  = leafopt.refl;
        tau(1:60,IwlP)  = leafopt.tran;
        rlast    = rho(:,nwlP);
        tlast    = tau(:,nwlP);

        rs(IwlP) = rsfile(:,soil.spectrum+1);
        rslast   = rs(nwlP);
        
        switch options.rt_thermal
            case 0                            
                rho(:,IwlT) = ones(60,nwlT) * leafbio.rho_thermal;               
                tau(:,IwlT) = ones(60,nwlT) * leafbio.tau_thermal;
                rs(IwlT)  = ones(nwlT,1) * soil.rs_thermal;
            case 1
                rho(:,IwlT) = ones(60,nwlT) * rlast;
                tau(:,IwlT) = ones(60,nwlT) * tlast;
                rs(IwlT)    = ones(1,nwlT) * rslast;
        end
        leafopt.refl = rho;     % extended wavelength ranges are stored in structures
        leafopt.tran = tau;
        soil.refl    = rs;
        soil.Ts      = meteo.Ta * ones(2,1);       % initial soil surface temperature        
        if length(F(4).FileName)>1 && options.simulation==0
            atmfile     = [path_input 'radiationdata/' char(F(4).FileName(k))];
            atmo.M      = aggreg(atmfile,spectral.SCOPEspec);
        end
        atmo.Ta     = meteo.Ta;
        [rad,gap,profiles]   = RTMo_m(spectral,atmo,soil,leafopt,canopy,angles,meteo,rad,options,mly);
        switch options.calc_ebal
            case 1
                [iter,fluxes,rad,thermal,profiles,soil]                          ...
                    = ebal(iter,options,spectral,rad,gap,                       ...
                    leafopt,angles,meteo,soil,canopy,leafbio,xyt,k,profiles);
                
                if options.calc_fluor
                    if options.calc_vert_profiles
                        [rad,profiles] = RTMf_m(spectral,rad,soil,leafopt,canopy,gap,angles,profiles);
                    else
                        [rad] = RTMf_m(spectral,rad,soil,leafopt,canopy,gap,angles,profiles);
                    end
                end
                
                if options.calc_planck
                    rad         = RTMt_planck(spectral,rad,soil,leafopt,canopy,gap,angles,thermal.Tcu,thermal.Tch,thermal.Ts(2),thermal.Ts(1),1);
                end
                
                if options.calc_directional
                    directional = calc_brdf(options,directional,spectral,angles,rad,atmo,soil,leafopt,canopy,meteo,profiles,thermal,leafbio);
                end
                
            otherwise
                
                Fc              = (1-gap.Ps(1:end-1))'/nl;      %           Matrix containing values for Ps of canopy
                fluxes.aPAR     = canopy.LAI*(Fc*rad.Pnh        + meanleaf(canopy,rad.Pnu    , 'angles_and_layers',gap.Ps));% net PAR leaves
                fluxes.aPAR_Cab = canopy.LAI*(Fc*rad.Pnh_Cab    + meanleaf(canopy,rad.Pnu_Cab, 'angles_and_layers',gap.Ps));% net PAR leaves
                fluxes.aPAR_Wm2 = canopy.LAI*(Fc*rad.Rnh_PAR    + meanleaf(canopy,rad.Rnu_PAR, 'angles_and_layers',gap.Ps));% net PAR leaves
                if options.calc_fluor
                    profiles.etah = ones(60,1);
                    profiles.etau = ones(13,36,60);
                    if options.calc_vert_profiles
                        [rad,profiles] = RTMf_m(spectral,rad,soil,leafopt,canopy,gap,angles,profiles);
                    else
                        [rad] = RTMf_m(spectral,rad,soil,leafopt,canopy,gap,angles,profiles);
                    end
                end
        end
        
        output_data
    end
    if options.simulation==2 && telmax>1, vi  = count_x(nvars,vi,vmax,1); end
end

if options.verify
    output_verification
end

if options.makeplots
    plots
end
