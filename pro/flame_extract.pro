

;*******************************************************************************
;*******************************************************************************
;*******************************************************************************



PRO flame_extract_slit, fuel, slit, dir=dir


	; read data and make spatial profile
	; ----------------------------------------------------------------------------

	cgPS_open, dir + 'profile.' + string(slit.number, format='(I03)') + '.' + slit.name + '.ps'

	; output file to be used for the extraction
	filename_spec2d = slit.output_file

  ; read in 2d spectrum
  spec2d = mrdfits(filename_spec2d, 0, header, /silent)

  ; read in 2d error spectrum
	; WARNING: USING THE 'EMPIRICAL' ESTIMATE - this may be bad if you have too few frames
  err2d = mrdfits(filename_spec2d, 2, /silent)

  ; create ivar image
  ivar2d = 1d/err2d^2

  ; read in wavelength axis
	lambda_1d = sxpar(header,'CRVAL1') + (findgen(sxpar(header,'NAXIS1')) - sxpar(header,'CRPIX1') + 1d) * sxpar(header,'CDELT1')

  ; spatial axis
  y_1d = findgen(sxpar(header,'NAXIS2'))

	; integrate 2d spectrum
  profile = total(spec2d, 1, /nan)

	; show spatial profile
	cgplot, y_1d, profile, charsize=1, $
		xtitle='Position along the slit (pixel)', ytitle='Total flux', $
		title = 'black: observed flux; red: Gaussian fit to the peak; orange: boxcar window'

	; cut away non positive pixels
	profile[where(profile LT 0.0, /null)] = 0.0


	; fit Gaussian to the peak
	; ----------------------------------------------------------------------------

	; estimate parameters of the Gaussian
	est_peak = max(profile)
  est_center = 0.5*n_elements(profile)
	est_sigma = 2.0
	est_cont = median(profile)
	est_param = [est_peak, est_center, est_sigma, est_cont]

	; Gaussian fit
	gaussian_model = gaussfit( y_1d, profile, gauss_param, nterms=4, $
		estimates=est_param, sigma=gauss_err, chisq=chisq )

	if ~finite(chisq) or $			; check that chi square makes sense
		gauss_param[0] LT 0.0 or $	; check that the peak of the Gaussian is positive
		gauss_param[0] LT 5.0*gauss_err[0] or $ 	; check that the SNR is high
	 	gauss_param[1] LT min(y_1d) or gauss_param[1] GT max(y_1d) or $ 			; check that the center of the Guassian is in the observed range
		gauss_param[2] LT 0.1 or gauss_param[2] GT n_elements(profile) $		 	; check that the Gaussian width makes sense
		then begin
			print, 'No object was detected in the slit'
			cgPS_close
			return
	endif

	; overplot the Gaussian fit
	x_axis = min(y_1d) + n_elements(y_1d) * dindgen(300)/299.0
	cgplot, x_axis, gauss_param[0] * exp( -0.5*( (x_axis-gauss_param[1])/gauss_param[2] )^2 ) + gauss_param[3], $
		/overplot, color='red'

	; overplot +/-2 sigma
	cgplot, [0,0] + gauss_param[1] + 2.0*gauss_param[2], [-1d5, 1d5], /overplot, color='red3'
	cgplot, [0,0] + gauss_param[1] - 2.0*gauss_param[2], [-1d5, 1d5], /overplot, color='red3'


	; boxcar extraction within +/- 2sigma
	; ----------------------------------------------------------------------------

	w_boxcar = where( abs(y_1d-gauss_param[1]) LT 2.0*gauss_param[2]+0.49, /null )
  trace2d = spec2d[*,w_boxcar]
  trace2d_ivar = ivar2d[*,w_boxcar]

  ; calculate boxcar extraction
  spec1d_boxcar = total(trace2d, 2)
  ivar1d_boxcar = 1. / total(1./trace2d_ivar, 2)

	; plot extracted spectrum
	xrange = [min(lambda_1d, /nan), max(lambda_1d, /nan)]
	cgplot, lambda_1d, ivarsmooth(spec1d_boxcar, ivar1d_boxcar, 7), $
		charsize=1, xtitle='Wavelength (um)', ytitle='Boxcar-extracted flux', $
		title = 'black: observed flux, blue; observed uncertainty', xrange=xrange, /xstyle
 	cgplot, lambda_1d, 1.0/sqrt(ivar1d_boxcar), /overplot, color='blue'


	; optimal extraction
	; ----------------------------------------------------------------------------

	; make weights using either the Gaussian fit or the observed profile
	if fuel.settings.extract_gaussian_profile then $
		weight1d = gaussian_model - gauss_param[3] else $
		weight1d = profile

	; cut the profile beyond three sigma
	weight1d[ where( abs(y_1d-gauss_param[1]) GT 3.0*gauss_param[2], /null ) ] = 0.0

	; normalize by the integral
	weight1d /= total(weight1d)

	; extend weight to 2d frame
	weight2d = replicate(1, (size(spec2d))[1] ) # weight1d

	; optimal extraction
  spec1d_optimal = total(weight2d*sqrt(ivar2d)*spec2d, 2, /nan) / total(weight2d^2*sqrt(ivar2d), 2, /nan)
  ivar1d_optimal = total(weight2d^2*ivar2d, 2, /nan)

	; plot extracted spectrum
	cgplot, lambda_1d, ivarsmooth(spec1d_optimal, ivar1d_optimal, 7), $
		charsize=1, xtitle='Wavelength (um)', ytitle='Optimally extracted flux', $
		title = 'black: observed flux, blue; observed uncertainty', xrange=xrange, /xstyle
 	cgplot, lambda_1d, 1.0/sqrt(ivar1d_optimal), /overplot, color='blue'


	; compare SNR
	; ----------------------------------------------------------------------------

	snr_boxcar = spec1d_boxcar * sqrt(ivar1d_boxcar)
	snr_optimal = spec1d_optimal * sqrt(ivar1d_optimal)

	erase
	cgplot, lambda_1d, snr_optimal, xtit='Wavelength (um)', ytit='SNR', $
		layout=[1,2,1], charsize=1, title='black: optimal extraction; gray: boxcar', xrange=xrange, /xstyle
	cgplot, lambda_1d, snr_boxcar, /overplot, color='blk4'

	cgplot, lambda_1d, median(snr_optimal/snr_boxcar-1.0, 7), $
		xtitle='Wavelength (um)', ytit='SNR optimal / SNR boxcar - 1', $
		layout=[1,2,2], charsize=1, yra=[-1,1], xrange=xrange, /xstyle

	cgplot, [0, 1d5], [0,0], /overplot, thick=2
	cgplot, [0, 1d5], 0.30+[0,0], /overplot, linestyle=2, thick=2, color='red'
	cgtext, xrange[0]+0.02*(xrange[1]-xrange[0]), 0.35, 'theoretical expectation', charsize=1, color='red'

	cgPS_close


	; write FITS file
	; ----------------------------------------------------------------------------

	; output optimal extraction
	if fuel.settings.extract_optimal then begin

		; filename for the output file
		filename = dir + 'spec1d.optimal.' + string(slit.number, format='(I03)') + '.' + slit.name + '.fits'

		; make nice output structure
		output_structure = { $
			lambda: lambda_1d, $
			flux: spec1d_optimal, $
			ivar: ivar1d_optimal }

	; output boxcar extraction
endif else begin

		; filename for the output file
		filename = dir + 'spec1d.boxcar.' + string(slit.number, format='(I03)') + '.' + slit.name + '.fits'

		; make nice output structure
		output_structure = { $
			lambda: lambda_1d, $
			flux: spec1d_boxcar, $
			ivar: ivar1d_boxcar }

	endelse

	; convert wavelength to angstrom in order to be compatible with SpecPro
	output_structure.lambda *= 1d4

	; make new FITS header, with units
	sxaddpar, header_output, 'TUNIT1', 'Angstrom'
	sxaddpar, header_output, 'TUNIT2', 'electron / (pix s)'
	sxaddpar, header_output, 'TUNIT3', 'electron / (pix s)'

	; write structure to FITS file
	mwrfits, output_structure, filename, header_output, /create


END



;*******************************************************************************
;*******************************************************************************
;*******************************************************************************


PRO flame_extract, fuel

	flame_util_module_start, fuel, 'flame_extract'

	; if needed, create extraction directory in the output directory
  extraction_dir = fuel.util.output_dir + 'extraction' + path_sep()
  if ~file_test(extraction_dir) then file_mkdir, extraction_dir

	; extract 1D spectrum for each slit
	for i_slit=0, n_elements(fuel.slits)-1 do begin

		if fuel.slits[i_slit].skip then continue

		; handle errors by ignoring that slit
		if fuel.settings.stop_on_error eq 0 then begin
			catch, error_status
			if error_status ne 0 then begin
				print, ''
		    print, '**************************'
		    print, '***       WARNING      ***'
		    print, '**************************'
		    print, 'Error found. Skipping slit ' + strtrim(fuel.slits[i_slit].number,2), ' - ', fuel.slits[i_slit].name
				fuel.slits[i_slit].skip = 1
				catch, /cancel
				continue
			endif
		endif

	  print, 'Extracting 1D spectrum for ' + strtrim(fuel.slits[i_slit].number,2), ' - ', fuel.slits[i_slit].name

		flame_extract_slit, fuel, fuel.slits[i_slit], dir=extraction_dir


	endfor


  flame_util_module_end, fuel


  print, '-------------------------------------'
	print, '-------------------------------------'
	print, '-------------------------------------'

	; print total execution time
	print, ' '
	print, 'The data reduction took a total of ', $
		cgnumber_formatter((systime(/seconds) - fuel.util.start_time)/60.0, decimals=2), ' minutes.'
		print, ' '

END
