// **********************************************************************
//
// Copyright (c) 1999
// Object Oriented Concepts, Inc.
// Billerica, MA, USA
//
// All Rights Reserved
//
// **********************************************************************

#include <OB/CORBA.h>

#include <apptest.h>

#include <stdlib.h>

#ifdef HAVE_STD_IOSTREAM
using namespace std;
#endif
using namespace AppTest;

int
run(CORBA::ORB_ptr orb, int argc, char* argv[])
{
    //
    // Get the object
    //
    CORBA::Object_var obj = orb -> string_to_object("relfile:/testing.ref");
    if(CORBA::is_nil(obj))
    {
    cerr << argv[0] << ": cannot read IOR from Factory.ref" << endl;
    return EXIT_FAILURE;
    }
    
    Testing_var testing = Testing::_narrow(obj);
    assert(!CORBA::is_nil(testing));
    
    //
    // Main loop
    //
    testing->say("Olá Tudo Bem?");


    return EXIT_SUCCESS;
}

int
main(int argc, char* argv[], char*[])
{
    int status = EXIT_SUCCESS;
    CORBA::ORB_var orb;

    try
    {
    orb = CORBA::ORB_init(argc, argv);
    status = run(orb, argc, argv);
    }
    catch(const CORBA::Exception& ex)
    {
    cerr << ex << endl;
    status = EXIT_FAILURE;
    }

    if(!CORBA::is_nil(orb))
    {
    try
    {
        orb->destroy();
    }
    catch(const CORBA::Exception& ex)
    {
        cerr << ex << endl;
        status = EXIT_FAILURE;
    }
    }
    
    return status;
}
