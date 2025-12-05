
.. _app_usb_aud_template:

Template USB Audio application
==============================

The ``app_usb_aud_template`` application is a minimal template for creating custom USB Audio designs
based on xcore.ai. It uses the XMOS USB Audio framework (``lib_xua``) and serves as a good starting
point for porting to custom hardware.

.. note::
   This template supports xcore.ai (XS3) only. Porting to xcore-200 (XS2), when using this template, is not supported.

It uses the XMOS USB Audio framework to implement a USB Audio device with the following default
key features:

- USB Audio Class 1.0/2.0 Compliant

- Fully Asynchronous operation

- 2 channels analogue input and 2 channels analogue output

- Support for the following sample frequencies: 44.1, 48, 88.2, 96, 176.4, 192 kHz

Build and run
-------------

The following instructions assume that the `XMOS XTC tools <https://www.xmos.com/software-tools/>`_ has
been downloaded and installed (see `README` for required version).

Installation instructions can be found `here <https://xmos.com/xtc-install-guide>`_. Particular
attention should be paid to the section `Installation of required third-party tools
<https://www.xmos.com/documentation/XM-014363-PC-10/html/installation/install-configure/install-tools/install_prerequisites.html>`_.

The application uses the `XMOS` build and dependency system,
`xcommon-cmake <https://www.xmos.com/file/xcommon-cmake-documentation/?version=latest>`_. `xcommon-cmake` is bundled with the `XMOS` XTC tools.

To configure the build, run the following from an XTC command prompt:

.. code-block:: console

    cd app_usb_aud_template
    cmake -G "Unix Makefiles" -B build

Any missing dependencies will be downloaded by the build system at this configure step.
To build the application, run ``xmake``:

.. code-block:: console

  xmake -j -C build

The application binary ``bin/app_usb_aud_template.xe`` is generated.

To run, connect the desired hardware to the host computer, and from the
``app_usb_aud_template`` directory, run:

.. code-block:: console

  xrun --xscope bin/app_usb_aud_template.xe

The device should enumerate as a 2 channel USB device on the host computer.

Customisation
-------------

Adapting to new hardware
^^^^^^^^^^^^^^^^^^^^^^^^

Update the ``app_usb_aud_template/src/core/custom_board.xn`` file to match the target hardware.

Enable features
^^^^^^^^^^^^^^^

Application-specific configuration should be done via ``app_usb_aud_template/src/core/xua_conf.h`` in the template app.
Override defaults from ``lib_xua`` (``xua_conf_default.h``) by defining the required macros in ``xua_conf.h``.

Audio hardware configuration
^^^^^^^^^^^^^^^^^^^^^^^^^^^^

By default, the template application does not configure any ADC/DAC. Codec support can be added by
implementing the :c:func:`AudioHwInit()` and :c:func:`AudioHwConfig()` hooks in ``app_usb_aud_template/src/extensions/audiohw.xc``

These are invoked from ``XUA_AudioHub()`` on the Audio tile (``XUA_AUDIO_IO_TILE_NUM``).

.. note::

    Codec configuration typically needs to be done over I²C. An
    `I²C master interface <https://www.xmos.com/file/lib_i2c>`_
    must be instantiated on the tile on which the I²C ports are present and
    accessed from the audio tile (``XUA_AUDIO_IO_TILE_NUM``) when configuring the codec.

    Optional headers files (``xua_conf_tasks.h``, ``xua_conf_globals.h`` and ``xua_conf_declarations.h``),
    added to ``app_usb_aud_template/src/core``,
    must be used to add custom tasks and declarations (such as the ``i2c_master()`` task and the
    ``i2c_master_if`` XCORE interface)
    Refer to ``app_usb_aud_xk_316_mc/src/core/xua_conf_tasks.h`` and
    ``app_usb_aud_xk_316_mc/src/core/xua_conf_globals.h`` for an example of this.
