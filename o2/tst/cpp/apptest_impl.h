#ifndef ___apptest_impl_h__
#define ___apptest_impl_h__

#include <apptest_skel.h>

//
// IDL:AppTest:1.0
//
namespace AppTest
{

//
// IDL:AppTest/Testing:1.0
//
class Testing_impl : virtual public POA_AppTest::Testing,
                     virtual public PortableServer::RefCountServantBase
{
    Testing_impl(const Testing_impl&);
    void operator=(const Testing_impl&);

    PortableServer::POA_var poa_;

public:

    Testing_impl(PortableServer::POA_ptr);
    ~Testing_impl();

    virtual PortableServer::POA_ptr _default_POA();

    //
    // IDL:AppTest/Testing/say:1.0
    //
    virtual void say(const char* text)
        throw(CORBA::SystemException);
};

} // End of namespace AppTest

#endif
