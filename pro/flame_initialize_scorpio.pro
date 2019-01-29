; SCORPIO-specific routines that initialize the fuel structure

FUNCTION flame_initialize_scorpio_instrument, science_header
; Read SCORPIO settings from FITS header of a science frame and create
; instrument structure

	disperser = strtrim(fxpar(science_header, 'DISPERSE'), 2)
	grating_name = (strsplit(disperser, /extract))[0]
	pixel_scale = (strsplit(strtrim(fxpar(science_header, 'IMSCALE'), 2), 'x', /extract))[1]
	gain = float(fxpar(science_header, 'GAIN'))
	rdnoise = float(fxpar(science_header, 'RDNOISE'))

	case grating_name of
		'VPHG400': R = 500.
		'VPHG550G': R = 535.
		'VPHG550R': R = 800.
		'VPHG1200B': R = 818.
		'VPHG1200G': R = 970.
		'VPHG1200R': R = 1320.
		'VPHG1200IR': R = 1690.
		'VPHG1800_O': R = 2400.
		'VPHG1800R': R = 2660.
		'VPHG3000B': R = 2530.
		else: message, grating_name + ' not supported'
	endcase

	instrument = { $
		instrument_name:'SCORPIO', $
		pixel_scale:pixel_scale, $
		gain:gain, $
		readnoise:rdnoise, $
		resolution_slit1arcsec:R, $
		linearity_correction:[0., 1.], $
		default_badpixel_mask:'none', $
		default_dark:'none', $
		default_pixelflat:'none', $
		default_arc:'none' $
		}

	return, instrument

END

FUNCTION flame_initialize_scorpio_longslit, science_header, instrument, input

	PA = !values.d_nan ; Can probably be calculated from header

	if array_equal(input.longslit_edge, [0, 0]) then $
		yrange = [1, 1024] else $
		yrange = input.longslit_edge

	width = float((strsplit(fxpar(science_header, 'FILTERS'), '_', /extract))[1])

	disperser = strtrim(fxpar(science_header, 'DISPERSE'), 2)
	grating_name = (strsplit(disperser, /extract))[0]
	delta_lambda = float((strsplit(disperser, /extract))[1])
	lambda0 = float((strsplit(fxpar(science_header, 'SPERANGE'), '-', /extract))[0])
	; convert from A to um
	range_lambda0 = [0.95, 1.15]*lambda0/1e4
	range_delta_lambda = [0.5, 1.5]*delta_lambda/1e4

	longslit = flame_util_create_slitstructure( $
		number = 1, $
		name = 'longslit', $
		PA = PA, $
		approx_bottom = yrange[0], $
		approx_top = yrange[1], $
		approx_target = mean(yrange), $
		width_arcsec = width, $
		approx_R = instrument.resolution_slit1arcsec, $
		range_lambda0 = range_lambda0, $
		range_delta_lambda = range_delta_lambda )

	return, longslit

END

FUNCTION flame_initialize_scorpio, input

	print,''
	print, 'Initializing SCORPIO data reduction'
	print, ''

	fuel = flame_util_create_fuel(input)
	science_header = headfits(fuel.util.science.raw_files[0])
	instrument = flame_initialize_scorpio_instrument(science_header)
	slits = flame_initialize_scorpio_longslit(science_header, instrument, input)
	disperser = strtrim(fxpar(science_header, 'DISPERSE'), 2)
	grating_name = (strsplit(disperser, /extract))[0]

	; Set trim region and linelist based on grating
	if array_equal(fuel.settings.trim_slit, [0,0]) then begin
		case grating_name of
			'VPHG550G': BEGIN
				fuel.settings.trim_slit = [300, 2067]
				linelist_arc = fuel.util.flame_data_dir + 'Scorpio/VPHG550G.dat'
			END
			else: message, grating_name, ' not supported'
		endcase
	endif

	; select sky linelist based on R
	if slits.approx_R LT 2000.0 then begin
		linelist_sky = fuel.util.flame_data_dir + 'linelist_sky_R1000.dat'
	endif else begin
		linelist_sky = fuel.util.flame_data_dir + 'linelist_sky_R3000.dat'
	endelse

	; copy linelists to intermediate dir
	file_copy, linelist_arc, fuel.util.intermediate_dir, /overwrite
	file_copy, linelist_sky, fuel.util.intermediate_dir, /overwrite
	fuel.settings.linelist_arcs_filename = fuel.util.intermediate_dir + file_basename(linelist_arc)
	fuel.settings.linelist_sky_filename = fuel.util.intermediate_dir + file_basename(linelist_sky)
	fuel.settings.sky_emission_filename = fuel.util.flame_data_dir + 'sky_emission_model_optical.dat'

	fuel.settings.roughwavecal_split=0
	fuel.settings.wavesolution_order_x = 5
	fuel.settings.wavesolution_order_y = 5
	fuel.settings.badpix_useflat = 0
	fuel.settings.combine_ccdreject = 1

	; save both instrument and slits in the fuel structure
	new_fuel = { input:fuel.input, settings:fuel.settings, util:fuel.util, instrument:instrument, diagnostics:fuel.diagnostics, slits:slits }

	return, new_fuel

END
