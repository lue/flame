


PRO flame_rectify_one, filename=filename, rectification=rectification, output_name=output_name, slit=slit

	print, 'rectifying ', filename

	; read in file to rectify
	im = mrdfits(filename, 0, header, /silent)
	im_sigma = mrdfits(filename, 1, /silent)

	; read dimensions of the image
	N_imx = (size(im))[1]
	N_imy = (size(im))[2]

	; make the new, regular pixel grid
	lambda_0 = slit.outlambda_min
	delta_lambda = slit.outlambda_delta
	Nx = slit.outlambda_Npix
	Ny = N_imy

	; resample image onto new grid
	new_im = poly_2D(im, rectification.Kx, rectification.Ky, 1, Nx, Ny, missing=!values.d_nan )
	new_im_sigma = poly_2D(im_sigma, rectification.Kx, rectification.Ky, 1, Nx, Ny, missing=!values.d_nan )

	;************** take care of NaNs
	; NOTE: what you really want to do is to calculate the inverse transformation
	; from real_y,lambda back to x,y and check for each pixel whether that was a NaN
	;***************

	; *********** wait a minute, I think that poly_2d treats NaNs correctly!!!!

	; add the wavelength calibration to the FITS header
	SXADDPAR, Header, 'CTYPE1', 'AWAV    '
	SXADDPAR, Header, 'CUNIT1', 'MICRON'
	SXADDPAR, Header, 'CRPIX1', 1
	SXADDPAR, Header, 'CRVAL1', lambda_0
	SXADDPAR, Header, 'CDELT1', delta_lambda

	; add the spatial position to the FITS header
	SXADDPAR, Header, 'CUNIT2', 'PIXEL'
	SXADDPAR, Header, 'CRPIX2', 1
	SXADDPAR, Header, 'CRVAL2', 1.0
	SXADDPAR, Header, 'CDELT2', 1.0

	; delete WCS keywords
	SXDELPAR, Header, 'CTYPE2'
	SXDELPAR, Header, 'CD1_1'
	SXDELPAR, Header, 'CD1_2'
	SXDELPAR, Header, 'CD2_1'
	SXDELPAR, Header, 'CD2_2'

	; write rectified image
	writefits, output_name, new_im, header
	writefits, output_name, new_im_sigma, /append

END


; ---------------------------------------------------------------------------------------------------------------------------


PRO flame_rectify, fuel

		start_time = systime(/seconds)

	  print, ''
	  print, '-------------------------------------'
	  print, '---         flame_rectify         ---'
	  print, '-------------------------------------'
	  print, ''


	; loop through all slits
	for i_slit=0, n_elements(fuel.slits)-1 do begin

		this_slit = fuel.slits[i_slit]

		print, 'Rectifying slit ', this_slit.number, ' - ', this_slit.name

		for i_frame=0, n_elements(this_slit.cutouts)-1 do begin

			this_cutout = this_slit.cutouts[i_frame]

			filename = this_cutout.filename

			; rectify observed frame
			flame_rectify_one, filename=filename, rectification=(*this_cutout.rectification), $
				output_name = flame_util_replace_string(filename, '.fits', '_rectified.fits'), slit=this_slit

			; rectify sky-subtracted frame
			flame_rectify_one, filename=flame_util_replace_string(filename, '.fits', '_skysub.fits'), rectification=(*this_cutout.rectification), $
				output_name = flame_util_replace_string(filename, '.fits', '_skysub_rectified.fits'), slit=this_slit

		endfor

	endfor


	print, ''
  print, 'flame_rectify took ', $
    cgnumber_formatter( systime(/seconds) - start_time, decimals=2), ' seconds'
  print, ''

END